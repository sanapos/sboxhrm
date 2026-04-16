import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/attendance.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';

enum _SyncStatus { starting, deleting, syncing, completed, error }

class _SyncProgress {
  final String deviceId;
  final String deviceName;
  _SyncStatus status;
  String message;
  double progress;
  _SyncProgress({
    required this.deviceId,
    required this.deviceName,
  })  : status = _SyncStatus.starting,
        message = 'Đang chuẩn bị...',
        progress = 0;
}

/// Màn hình hiển thị dữ liệu chấm công real-time từ máy chấm công
class DeviceAttendanceScreen extends StatefulWidget {
  const DeviceAttendanceScreen({super.key});

  @override
  State<DeviceAttendanceScreen> createState() => _DeviceAttendanceScreenState();
}

class _DeviceAttendanceScreenState extends State<DeviceAttendanceScreen> {
  final ApiService _apiService = ApiService();
  final SignalRService _signalR = SignalRService();

  // Data
  List<Attendance> _attendances = [];
  List<dynamic> _devices = [];
  bool _isLoading = false;
  int _totalCount = 0;
  int _currentPage = 1;
  int _pageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Filters
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 1));
  DateTime _toDate = DateTime.now();
  String? _selectedDeviceId;
  Set<String> _selectedEmployeePins = {}; // PINs of selected employees
  int? _filterAttendanceState; // null = tất cả
  int? _filterVerifyMode; // null = tất cả
  String _selectedPreset = 'today';

  // Sorting
  String _sortColumn = 'time';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileFilters = false;

  // Real-time
  StreamSubscription? _attendanceSub;
  final List<Attendance> _realtimeQueue = [];
  bool _showRealtimeBanner = false;

  // Calculated punch order: attendanceId -> calculated state (0=Vào, 1=Ra)
  final Map<String, int> _calculatedStates = {};

  // Giờ kết thúc ngày (day_end_time) - lấy từ system settings
  // Nếu day_end_time = 05:00 → các lần chấm trước 05:00 thuộc ngày làm việc hôm trước
  int _dayEndHour = 0;
  int _dayEndMinute = 0;

  // Export
  final GlobalKey _tableKey = GlobalKey();
  bool _isExporting = false;

  // Sync progress tracking
  final Map<String, _SyncProgress> _activeSyncs = {};

  // Date formatters
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _timeFormat = DateFormat('HH:mm:ss');
  final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
      _setupRealtime();
    });
  }

  @override
  void dispose() {
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    await Future.wait([
      _loadDevices(),
      _loadDayEndTime(),
    ]);
    await _loadAttendances();
  }

  /// Load giờ kết thúc ngày từ system settings
  Future<void> _loadDayEndTime() async {
    try {
      final result = await _apiService.getAppSetting('day_end_time');
      if (result['isSuccess'] == true && result['data'] is Map) {
        final data = result['data'] as Map;
        final value = data['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          _dayEndHour = int.tryParse(parts[0]) ?? 0;
          _dayEndMinute = int.tryParse(parts[1]) ?? 0;
        }
      }
    } catch (e) {
      debugPrint('Error loading day_end_time: $e');
    }
  }

  void _setupRealtime() {
    _attendanceSub = _signalR.onNewAttendance.listen((att) {
      if (!mounted) return;
      // Check if attendance matches current filters
      bool matchesDevice = _selectedDeviceId == null ||
          att.deviceId == _selectedDeviceId;
      bool matchesDate = att.attendanceTime.isAfter(_fromDate) &&
          att.attendanceTime.isBefore(_toDate.add(const Duration(days: 1)));

      if (matchesDevice && matchesDate) {
        setState(() {
          _realtimeQueue.insert(0, att);
          _showRealtimeBanner = true;
          // Auto-add to list if on first page
          if (_currentPage == 1) {
            _attendances.insert(0, att);
            _totalCount++;
            // Recalculate states with the new attendance
            _calculatePunchStates(_attendances);
          }
        });
      }
    });
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _apiService.getDevices(storeOnly: true);
      if (mounted) {
        setState(() {
          // Deduplicate devices by ID to avoid dropdown assertion errors
          final seen = <String>{};
          _devices = devices.where((d) {
            final id = d['id']?.toString() ?? '';
            if (id.isEmpty || seen.contains(id)) return false;
            seen.add(id);
            return true;
          }).toList();
        });
      }
    } catch (e) {
      // Device loading failed silently
    }
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'today':
          _fromDate = today;
          _toDate = now;
          break;
        case 'yesterday':
          final yesterday = today.subtract(const Duration(days: 1));
          _fromDate = yesterday;
          _toDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          break;
        case 'week':
          final weekday = now.weekday;
          _fromDate = today.subtract(Duration(days: weekday - 1));
          _toDate = now;
          break;
        case 'lastWeek':
          final weekday = now.weekday;
          final thisMonday = today.subtract(Duration(days: weekday - 1));
          _fromDate = thisMonday.subtract(const Duration(days: 7));
          final lastSunday = thisMonday.subtract(const Duration(days: 1));
          _toDate = DateTime(lastSunday.year, lastSunday.month, lastSunday.day, 23, 59, 59);
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'lastMonth':
          _fromDate = DateTime(now.year, now.month - 1, 1);
          final lastDay = DateTime(now.year, now.month, 0);
          _toDate = DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
          break;
        case 'all':
          _fromDate = DateTime(2020, 1, 1);
          _toDate = now;
          break;
      }
    });
    _loadAttendances();
  }

  Future<void> _loadAttendances({bool resetPage = true}) async {
    if (_isLoading) return;
    if (resetPage) _currentPage = 1;

    setState(() {
      _isLoading = true;
      _showRealtimeBanner = false;
      _realtimeQueue.clear();
    });

    try {
      // Determine device IDs to query
      List<String> deviceIds;
      if (_selectedDeviceId != null) {
        deviceIds = [_selectedDeviceId!];
      } else {
        deviceIds = _devices
            .map((d) => d['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }

      if (deviceIds.isEmpty) {
        setState(() {
          _attendances = [];
          _totalCount = 0;
          _isLoading = false;
        });
        return;
      }

      final result = await _apiService.getAttendances(
        deviceIds: deviceIds,
        fromDate: _fromDate,
        toDate: _toDate,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        final items = (result['items'] as List?)
                ?.map((item) => Attendance.fromJson(item))
                .toList() ??
            [];

        _calculatePunchStates(items);

        setState(() {
          _attendances = items;
          _totalCount = result['totalCount'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Lỗi tải dữ liệu: $e');
      }
    }
  }

  /// Tính kiểu chấm công theo thứ tự lẻ/chẵn cho mỗi nhân viên trong ngày làm việc.
  /// Lần chấm lẻ (1, 3, 5...) = Vào (0), lần chẵn (2, 4, 6...) = Ra (1)
  /// Group by employeeId (EmployeeCode from HR) để gộp các PIN khác nhau trên các thiết bị khác nhau.
  /// Sử dụng day_end_time để xác định ranh giới ngày làm việc:
  /// VD: day_end_time = 05:00 → lần chấm lúc 04:24 ngày 05/03 thuộc ngày làm việc 04/03
  void _calculatePunchStates(List<Attendance> attendances) {
    _calculatedStates.clear();

    // day_end_time as Duration for comparison
    final dayEndDuration = Duration(hours: _dayEndHour, minutes: _dayEndMinute);

    // Group by employeeId (Mã NV) + working day — ưu tiên employeeId vì cùng 1 nhân viên có thể có PIN khác nhau trên các thiết bị
    final Map<String, List<Attendance>> groups = {};
    for (final att in attendances) {
      final empKey = att.employeeId ?? att.pin ?? att.id;
      // Tính ngày làm việc: nếu giờ chấm < day_end_time → thuộc ngày hôm trước
      var workingDay = DateTime(att.attendanceTime.year, att.attendanceTime.month, att.attendanceTime.day);
      if (dayEndDuration > Duration.zero) {
        final punchTime = Duration(hours: att.attendanceTime.hour, minutes: att.attendanceTime.minute, seconds: att.attendanceTime.second);
        if (punchTime < dayEndDuration) {
          workingDay = workingDay.subtract(const Duration(days: 1));
        }
      }
      final key = '${empKey}_${workingDay.year}-${workingDay.month}-${workingDay.day}';
      groups.putIfAbsent(key, () => []).add(att);
    }

    // For each group, sort by time and assign odd=CheckIn, even=CheckOut
    for (final group in groups.values) {
      group.sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));
      for (int i = 0; i < group.length; i++) {
        // i=0 → lần 1 (lẻ) → Vào, i=1 → lần 2 (chẵn) → Ra, ...
        _calculatedStates[group[i].id] = (i % 2 == 0) ? 0 : 1;
      }
    }
  }

  /// Lấy kiểu chấm đã tính toán (0=Vào, 1=Ra) 
  int _getCalculatedState(Attendance att) {
    return _calculatedStates[att.id] ?? att.attendanceState;
  }

  String _getCalculatedStateText(int state) {
    switch (state) {
      case 0: return 'Vào';
      case 1: return 'Ra';
      default: return 'Không xác định';
    }
  }

  // ==================== EDIT / DELETE ATTENDANCE ====================

  /// Show dialog to edit attendance time
  Future<void> _showEditAttendanceDialog(Attendance att) async {
    DateTime editDate = att.attendanceTime;
    TimeOfDay editTime = TimeOfDay.fromDateTime(att.attendanceTime);
    bool isSaving = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_calendar, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 8),
                const Text('Sửa giờ chấm công'),
              ],
            ),
            content: SizedBox(
              width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Employee info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: Colors.grey.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                att.employeeName ?? att.deviceUserName ?? 'N/A',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Mã NV: ${att.employeeId ?? att.pin ?? "—"}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Original time
                  Text('Giờ chấm gốc:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm:ss').format(att.attendanceTime),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  Text('Chỉnh sửa:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  // Date picker
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: editDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                editDate = DateTime(
                                  picked.year, picked.month, picked.day,
                                  editTime.hour, editTime.minute, att.attendanceTime.second,
                                );
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  _dateFormat.format(editDate),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: editTime,
                              builder: (context, child) {
                                return MediaQuery(
                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setDialogState(() {
                                editTime = picked;
                                editDate = DateTime(
                                  editDate.year, editDate.month, editDate.day,
                                  picked.hour, picked.minute, att.attendanceTime.second,
                                );
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 18, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  '${editTime.hour.toString().padLeft(2, '0')}:${editTime.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Show new time preview
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_forward, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Giờ mới: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(editDate)}',
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppDialogActions(
                onCancel: () => Navigator.pop(ctx, false),
                onConfirm: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final newTime = DateTime(
                          editDate.year, editDate.month, editDate.day,
                          editTime.hour, editTime.minute, att.attendanceTime.second,
                        );
                        final success = await _apiService.updateAttendance(
                          att.id,
                          attendanceTime: newTime,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx, success);
                        }
                      },
                confirmLabel: 'Lưu',
                confirmIcon: Icons.save,
                isLoading: isSaving,
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã cập nhật giờ chấm công');
      }
      _loadAttendances(resetPage: false);
    } else if (confirmed == false) {
      _showError('Không thể cập nhật giờ chấm công');
    }
  }

  /// Delete attendance with confirmation
  Future<void> _deleteAttendance(Attendance att) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red.shade700, size: 24),
            const SizedBox(width: 8),
            const Text('Xóa chấm công'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn xóa bản ghi chấm công này?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    att.employeeName ?? att.deviceUserName ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mã NV: ${att.employeeId ?? att.pin ?? "—"}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  Text(
                    'Giờ chấm: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(att.attendanceTime)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  Text(
                    'Thiết bị: ${att.deviceName ?? "—"}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lưu ý: Hành động này không thể hoàn tác!',
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _apiService.deleteAttendance(att.id);
    if (success) {
      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa bản ghi chấm công');
      }
      _loadAttendances(resetPage: false);
    } else {
      _showError('Không thể xóa bản ghi chấm công');
    }
  }

  // ==================== EXPORT EXCEL / PDF / PNG ====================

  String _getVerifyModeText(int mode) {
    switch (mode) {
      case 0: return 'Mật khẩu';
      case 1: return 'Vân tay';
      case 2: return 'Thẻ';
      case 9: return 'Khuôn mặt';
      case 15: return 'Khuôn mặt';
      case 100: return 'Thủ công';
      default: return 'Khác';
    }
  }

  /// Export filtered attendance data to Excel (.xlsx)
  Future<void> _exportToExcel() async {
    final data = _filteredAttendances;
    if (data.isEmpty) {
      _showError('Không có dữ liệu để xuất');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final excelFile = excel_lib.Excel.createExcel();
      final sheet = excelFile['Chấm công'];
      // Remove default sheet
      if (excelFile.sheets.containsKey('Sheet1')) {
        excelFile.delete('Sheet1');
      }

      // Header style
      final headerStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#1565C0'),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        fontSize: 11,
      );

      // Title row
      final titleStyle = excel_lib.CellStyle(
        bold: true,
        fontSize: 14,
      );
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          excel_lib.TextCellValue('Dữ liệu chấm công trên máy');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = titleStyle;
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 0));

      // Date range info
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          excel_lib.TextCellValue('Từ ${_dateFormat.format(_fromDate)} đến ${_dateFormat.format(_toDate)} · ${data.length} bản ghi · Xuất lúc ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
          excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 1));

      // Headers
      final headers = ['STT', 'Mã NV', 'Tên nhân viên', 'Thiết bị', 'Ngày', 'Thứ', 'Giờ chấm', 'Kiểu chấm', 'Phương thức'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3));
        cell.value = excel_lib.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // Set column widths
      sheet.setColumnWidth(0, 6);   // STT
      sheet.setColumnWidth(1, 12);  // Mã NV
      sheet.setColumnWidth(2, 25);  // Tên NV
      sheet.setColumnWidth(3, 18);  // Thiết bị
      sheet.setColumnWidth(4, 13);  // Ngày
      sheet.setColumnWidth(5, 6);   // Thứ
      sheet.setColumnWidth(6, 12);  // Giờ chấm
      sheet.setColumnWidth(7, 12);  // Kiểu chấm
      sheet.setColumnWidth(8, 13);  // Phương thức

      // Data rows
      final dataCellStyle = excel_lib.CellStyle(fontSize: 11);
      for (int i = 0; i < data.length; i++) {
        final att = data[i];
        final calcState = _getCalculatedState(att);
        final row = i + 4; // Start after header (row 3)

        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          ..value = excel_lib.IntCellValue(i + 1)
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          ..value = excel_lib.TextCellValue(att.employeeId ?? att.pin ?? '')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          ..value = excel_lib.TextCellValue(att.employeeName ?? att.deviceUserName ?? '')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          ..value = excel_lib.TextCellValue(att.deviceName ?? '')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          ..value = excel_lib.TextCellValue(_dateFormat.format(att.attendanceTime))
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          ..value = excel_lib.TextCellValue(_getDayOfWeek(att.attendanceTime))
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          ..value = excel_lib.TextCellValue(_timeFormat.format(att.attendanceTime))
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          ..value = excel_lib.TextCellValue(_getCalculatedStateText(calcState))
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
          ..value = excel_lib.TextCellValue(_getVerifyModeText(att.verifyMode))
          ..cellStyle = dataCellStyle;
      }

      // Save and download
      final bytes = excelFile.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel');

      final fileName = 'ChamCong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: 'Đã xuất Excel: $fileName (${data.length} bản ghi)');
      }
    } catch (e) {
      _showError('Lỗi xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Export filtered attendance data to PDF
  Future<void> _exportToPdf() async {
    final data = _filteredAttendances;
    if (data.isEmpty) {
      _showError('Không có dữ liệu để xuất');
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Load a font that supports Vietnamese
      final font = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      final pdf = pw.Document();
      const titleText = 'Dữ liệu chấm công trên máy';
      final subText = 'Từ ${_dateFormat.format(_fromDate)} đến ${_dateFormat.format(_toDate)} · ${data.length} bản ghi';
      final exportTime = 'Ngày xuất: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}';

      // Split data into pages (rows per page)
      const rowsPerPage = 30;
      final totalPages = (data.length / rowsPerPage).ceil();

      for (int page = 0; page < totalPages; page++) {
        final startIdx = page * rowsPerPage;
        final endIdx = (startIdx + rowsPerPage).clamp(0, data.length);
        final pageData = data.sublist(startIdx, endIdx);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(24),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (page == 0) ...[
                    pw.Text(titleText, style: pw.TextStyle(font: fontBold, fontSize: 16)),
                    pw.SizedBox(height: 4),
                    pw.Text(subText, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(height: 2),
                    pw.Text(exportTime, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                    pw.SizedBox(height: 12),
                  ],
                  if (page > 0)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Text('Trang ${page + 1}/$totalPages', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                    ),
                  pw.Expanded(
                    child: pw.TableHelper.fromTextArray(
                      headers: ['STT', 'Mã NV', 'Tên nhân viên', 'Thiết bị', 'Ngày', 'Thứ', 'Giờ chấm', 'Kiểu', 'P.Thức'],
                      data: pageData.asMap().entries.map((entry) {
                        final idx = startIdx + entry.key;
                        final att = entry.value;
                        final calcState = _getCalculatedState(att);
                        return [
                          '${idx + 1}',
                          att.employeeId ?? att.pin ?? '',
                          att.employeeName ?? att.deviceUserName ?? '',
                          att.deviceName ?? '',
                          _dateFormat.format(att.attendanceTime),
                          _getDayOfWeek(att.attendanceTime),
                          _timeFormat.format(att.attendanceTime),
                          _getCalculatedStateText(calcState),
                          _getVerifyModeText(att.verifyMode),
                        ];
                      }).toList(),
                      headerStyle: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white),
                      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF4F46E5)),
                      headerAlignment: pw.Alignment.center,
                      cellStyle: pw.TextStyle(font: font, fontSize: 8),
                      cellAlignment: pw.Alignment.centerLeft,
                      cellHeight: 22,
                      columnWidths: {
                        0: const pw.FixedColumnWidth(30),
                        1: const pw.FixedColumnWidth(55),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(1.5),
                        4: const pw.FixedColumnWidth(70),
                        5: const pw.FixedColumnWidth(30),
                        6: const pw.FixedColumnWidth(55),
                        7: const pw.FixedColumnWidth(40),
                        8: const pw.FixedColumnWidth(55),
                      },
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                      oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Trang ${page + 1}/$totalPages',
                      style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      final pdfBytes = await pdf.save();
      final fileName = 'ChamCong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.pdf';

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);

      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Xuất PDF', message: 'Đã xuất PDF: $fileName (${data.length} bản ghi)');
      }
    } catch (e) {
      _showError('Lỗi xuất PDF: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Capture data table as PNG image
  Future<void> _exportToPng() async {
    final data = _filteredAttendances;
    if (data.isEmpty) {
      _showError('Không có dữ liệu để xuất');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final boundary = _tableKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showError('Không tìm thấy bảng dữ liệu để chụp');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showError('Không thể tạo ảnh');
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      final fileName = 'ChamCong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');

      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh PNG: $fileName');
      }
    } catch (e) {
      _showError('Lỗi xuất PNG: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Gửi lệnh đồng bộ chấm công với chọn thiết bị & chế độ đồng bộ
  Future<void> _syncAttendancesFromDevices({DateTime? fromTime, DateTime? toTime}) async {
    if (_devices.isEmpty) {
      _showError('Không có thiết bị nào');
      return;
    }

    // Show dialog to select device and sync mode
    String? selectedDeviceId = _selectedDeviceId;
    // 'append' = bổ sung mới, 'replace' = xóa hết rồi ghi lại
    String syncMode = 'append';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.sync, color: Colors.blue.shade700, size: 24),
                  const SizedBox(width: 8),
                  Text(fromTime != null ? 'Đồng bộ theo thời gian' : 'Tải lại dữ liệu chấm công'),
                ],
              ),
              content: SizedBox(
                width: math.min(480, MediaQuery.of(context).size.width - 32).toDouble(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device selection
                    Text('Chọn máy chấm công:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedDeviceId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.router, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tất cả thiết bị')),
                        ..._devices.map((d) => DropdownMenuItem(
                              value: d['id']?.toString(),
                              child: Row(
                                children: [
                                  Icon(
                                    d['isOnline'] == true ? Icons.circle : Icons.circle_outlined,
                                    size: 10,
                                    color: d['isOnline'] == true ? Colors.green : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      d['deviceName'] ?? d['serialNumber'] ?? 'N/A',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedDeviceId = val),
                    ),
                    const SizedBox(height: 20),

                    // Sync mode
                    Text('Chế độ đồng bộ:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    // ignore: deprecated_member_use
                    RadioListTile<String>(
                      value: 'append',
                      // ignore: deprecated_member_use
                      groupValue: syncMode,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setDialogState(() => syncMode = v!),
                      title: const Text('Bổ sung chấm công mới'),
                      subtitle: const Text('Chỉ tải các bản ghi chấm công chưa có trên server'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    // ignore: deprecated_member_use
                    RadioListTile<String>(
                      value: 'replace',
                      // ignore: deprecated_member_use
                      groupValue: syncMode,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setDialogState(() => syncMode = v!),
                      title: const Text('Xóa hết và tải lại', style: TextStyle(color: Colors.red)),
                      subtitle: const Text('Xóa toàn bộ chấm công của máy trên DB, rồi tải lại từ đầu'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),

                    if (syncMode == 'replace')
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Dữ liệu chấm công hiện tại trên server của ${selectedDeviceId != null ? "máy đã chọn" : "TẤT CẢ máy"} sẽ bị xóa trước khi tải lại!',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (fromTime != null && toTime != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, color: Colors.blue.shade700, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Thời gian: ${_dateTimeFormat.format(fromTime)} → ${_dateTimeFormat.format(toTime)}',
                              style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                AppDialogActions(
                  onCancel: () => Navigator.pop(ctx, false),
                  onConfirm: () => Navigator.pop(ctx, true),
                  confirmLabel: syncMode == 'replace' ? 'Xóa và tải lại' : 'Đồng bộ',
                  confirmVariant: syncMode == 'replace' ? AppButtonVariant.danger : AppButtonVariant.primary,
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    // If replace mode, show second confirmation
    if (syncMode == 'replace') {
      if (!mounted) return;
      final confirmed2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700),
              const SizedBox(width: 8),
              const Text('Xác nhận xóa dữ liệu'),
            ],
          ),
          content: Text(
            'Bạn có CHẮC CHẮN muốn xóa toàn bộ dữ liệu chấm công '
            '${selectedDeviceId != null ? "của máy đã chọn" : "của TẤT CẢ máy"} '
            'trên server và tải lại từ đầu?\n\n'
            'Thao tác này KHÔNG THỂ hoàn tác.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            AppDialogActions.delete(
              onCancel: () => Navigator.pop(ctx, false),
              onConfirm: () => Navigator.pop(ctx, true),
              confirmLabel: 'Xác nhận xóa và tải lại',
            ),
          ],
        ),
      );
      if (confirmed2 != true) return;
    }

    // Determine which devices to sync
    final devices = selectedDeviceId != null
        ? _devices.where((d) => d['id']?.toString() == selectedDeviceId).toList()
        : _devices;

    // Start sync with progress overlay
    for (final device in devices) {
      final deviceId = device['id']?.toString();
      final deviceName = device['deviceName']?.toString() ?? device['serialNumber']?.toString() ?? 'N/A';
      if (deviceId == null) continue;

      // Kiểm tra thiết bị online trước khi đồng bộ
      final isOnline = await _apiService.isDeviceOnline(deviceId);
      if (!isOnline) {
        if (mounted) {
          _showError('Thiết bị "$deviceName" đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.');
        }
        continue;
      }

      final syncKey = '${deviceId}_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _activeSyncs[syncKey] = _SyncProgress(
          deviceId: deviceId,
          deviceName: deviceName,
        );
      });

      // Run sync in background (non-blocking)
      _executeSyncInBackground(
        syncKey: syncKey,
        deviceId: deviceId,
        deviceName: deviceName,
        syncMode: syncMode,
        fromTime: fromTime,
        toTime: toTime,
      );
    }
  }

  /// Execute sync for a single device in background with progress tracking
  Future<void> _executeSyncInBackground({
    required String syncKey,
    required String deviceId,
    required String deviceName,
    required String syncMode,
    DateTime? fromTime,
    DateTime? toTime,
  }) async {
    try {
      // Step 1: Delete if replace mode
      if (syncMode == 'replace') {
        _updateSyncProgress(syncKey, _SyncStatus.deleting, 'Đang xóa dữ liệu cũ...', 0.1);

        final deleteResult = await _apiService.deleteAttendancesByDevice(
          deviceId: deviceId,
          fromDate: fromTime,
          toDate: toTime,
        );
        if (deleteResult['isSuccess'] != true) {
          _updateSyncProgress(syncKey, _SyncStatus.error, 'Lỗi xóa dữ liệu cũ', 0);
          return;
        }
        _updateSyncProgress(syncKey, _SyncStatus.deleting, 'Đã xóa dữ liệu cũ', 0.3);
      }

      // Step 2: Send sync command to device (with date range if specified)
      _updateSyncProgress(syncKey, _SyncStatus.syncing, 'Đang gửi lệnh đồng bộ...', syncMode == 'replace' ? 0.4 : 0.2);

      final syncResult = await _apiService.syncAttendances(deviceId, fromTime: fromTime, toTime: toTime);
      final commandId = syncResult['data']?.toString() ?? syncResult['commandId']?.toString();
      if (commandId == null) {
        _updateSyncProgress(syncKey, _SyncStatus.error, 'Lỗi gửi lệnh đồng bộ', 0);
        return;
      }

      // Step 3: Poll command status cho đến khi hoàn thành
      _updateSyncProgress(syncKey, _SyncStatus.syncing, 'Đã gửi lệnh. Đang chờ máy chấm công tải dữ liệu...', 0.5);
      
      const maxWaitSeconds = 180; // 3 phút timeout
      const pollIntervalSeconds = 5;
      var elapsedSeconds = 0;
      var cmdStatus = 'Sent';
      
      while (elapsedSeconds < maxWaitSeconds) {
        await Future.delayed(const Duration(seconds: pollIntervalSeconds));
        elapsedSeconds += pollIntervalSeconds;
        
        if (!mounted) return;
        
        // Poll trạng thái command
        try {
          final statusData = await _apiService.getCommandStatus(commandId);
          if (statusData != null) {
            final statusValue = statusData['status']?.toString();
            // CommandStatus enum: Created=0, Sent=1, Success=2, Failed=3
            if (statusValue == '2' || statusValue == 'Success') {
              cmdStatus = 'Success';
              break;
            }
            if (statusValue == '3' || statusValue == 'Failed') {
              cmdStatus = 'Failed';
              break;
            }
          }
        } catch (e) {
          debugPrint('Error polling sync status: $e');
        }
        
        final progress = 0.5 + (elapsedSeconds / maxWaitSeconds) * 0.4; // 0.5 → 0.9
        _updateSyncProgress(
          syncKey, _SyncStatus.syncing, 
          'Đang chờ dữ liệu từ máy chấm công... (${elapsedSeconds}s)', 
          progress.clamp(0.5, 0.9),
        );
      }
      
      // Step 4: Kết quả
      if (cmdStatus == 'Success') {
        _updateSyncProgress(syncKey, _SyncStatus.completed, 'Hoàn tất đồng bộ! Dữ liệu đã được tải về.', 1.0);
      } else if (cmdStatus == 'Failed') {
        _updateSyncProgress(syncKey, _SyncStatus.error, 'Máy chấm công báo lỗi khi thực hiện lệnh', 0);
        return;
      } else {
        // Timeout - vẫn coi như thành công nếu lệnh đã gửi
        _updateSyncProgress(syncKey, _SyncStatus.completed, 'Lệnh đã gửi. Dữ liệu sẽ được tải về khi máy CC phản hồi.', 0.9);
      }

      // Reload data
      if (mounted) {
        await _loadAttendances();
      }

      // Auto-remove after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _activeSyncs.remove(syncKey);
          });
        }
      });
    } catch (e) {
      _updateSyncProgress(syncKey, _SyncStatus.error, 'Lỗi: $e', 0);
    }
  }

  void _updateSyncProgress(String syncKey, _SyncStatus status, String message, double progress) {
    if (!mounted) return;
    setState(() {
      final sync = _activeSyncs[syncKey];
      if (sync != null) {
        sync.status = status;
        sync.message = message;
        sync.progress = progress;
      }
    });
  }

  // ignore: unused_element
  Future<void> _showSyncByDateDialog() async {
    DateTime syncFrom = DateTime.now().subtract(const Duration(days: 7));
    DateTime syncTo = DateTime.now();

    final result = await showDialog<Map<String, DateTime>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.date_range, color: Colors.blue.shade700, size: 24),
                  const SizedBox(width: 8),
                  const Text('Chọn khoảng thời gian'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chọn khoảng thời gian để đồng bộ dữ liệu chấm công từ máy:'),
                  const SizedBox(height: 16),
                  _buildDatePickerRow(
                    label: 'Từ ngày',
                    date: syncFrom,
                    onChanged: (d) => setDialogState(() => syncFrom = d),
                  ),
                  const SizedBox(height: 8),
                  _buildDatePickerRow(
                    label: 'Đến ngày',
                    date: syncTo,
                    onChanged: (d) => setDialogState(() => syncTo = d),
                  ),
                ],
              ),
              actions: [
                AppDialogActions(
                  onConfirm: () => Navigator.pop(ctx, {'from': syncFrom, 'to': syncTo}),
                  confirmLabel: 'Tiếp tục',
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _fromDate = result['from']!;
        _toDate = result['to']!;
      });
      // Forward to the main sync dialog with date range
      await _syncAttendancesFromDevices(fromTime: result['from'], toTime: result['to']);
    }
  }

  Widget _buildDatePickerRow({
    required String label,
    required DateTime date,
    required ValueChanged<DateTime> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.grey)),
            const Spacer(),
            Text(_dateFormat.format(date), style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  /// Dialog chọn nhiều nhân viên với tìm kiếm
  Future<void> _showEmployeePickerDialog() async {
    final employees = _uniqueEmployees;
    final tempSelected = Set<String>.from(_selectedEmployeePins);
    String searchQuery = '';

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? employees
                : employees.where((e) {
                    final q = searchQuery.toLowerCase();
                    return (e['name'] ?? '').toLowerCase().contains(q) ||
                        (e['code'] ?? '').toLowerCase().contains(q) ||
                        (e['pin'] ?? '').toLowerCase().contains(q);
                  }).toList();

            final allFilteredSelected = filtered.isNotEmpty &&
                filtered.every((e) => tempSelected.contains(e['pin']));

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.people, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Text('Chọn nhân viên'),
                  const Spacer(),
                  if (tempSelected.isNotEmpty)
                    TextButton(
                      onPressed: () => setDialogState(() => tempSelected.clear()),
                      child: Text('Bỏ chọn tất cả (${tempSelected.length})'),
                    ),
                ],
              ),
              content: SizedBox(
                width: math.min(480, MediaQuery.of(context).size.width - 32).toDouble(),
                height: 450,
                child: Column(
                  children: [
                    // Search field
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Tìm theo tên, mã NV, PIN...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) =>
                          setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 8),

                    // Select all / count
                    Row(
                      children: [
                        Checkbox(
                          value: allFilteredSelected,
                          tristate: false,
                          onChanged: (val) {
                            setDialogState(() {
                              if (allFilteredSelected) {
                                for (final e in filtered) {
                                  tempSelected.remove(e['pin']);
                                }
                              } else {
                                for (final e in filtered) {
                                  tempSelected.add(e['pin']!);
                                }
                              }
                            });
                          },
                        ),
                        Text(
                          'Chọn tất cả (${filtered.length} nhân viên)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (tempSelected.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Đã chọn: ${tempSelected.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const Divider(height: 24),

                    // Employee list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                    size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 8),
                                  Text('Không tìm thấy nhân viên',
                                    style: TextStyle(
                                      color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final emp = filtered[i];
                                final pin = emp['pin']!;
                                final isSelected =
                                    tempSelected.contains(pin);
                                final name = emp['name'] ?? 'N/A';
                                final code = emp['code'] ?? pin;

                                // Count attendances for this employee
                                final attCount = _attendances
                                    .where((a) => a.pin == pin)
                                    .length;

                                return Material(
                                  color: isSelected
                                      ? Colors.blue.shade50
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        if (isSelected) {
                                          tempSelected.remove(pin);
                                        } else {
                                          tempSelected.add(pin);
                                        }
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: isSelected,
                                            onChanged: (val) {
                                              setDialogState(() {
                                                if (val == true) {
                                                  tempSelected.add(pin);
                                                } else {
                                                  tempSelected.remove(pin);
                                                }
                                              });
                                            },
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                Colors.blue.shade100,
                                            child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    Colors.blue.shade700),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    fontSize: 13,
                                                    color: isSelected
                                                        ? Colors
                                                            .blue.shade800
                                                        : null,
                                                  ),
                                                ),
                                                Text(
                                                  'Mã: $code  ·  PIN: $pin',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors
                                                        .grey.shade500),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 8,
                                                vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$attCount lần',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    Colors.grey.shade600),
                                            ),
                                          ),
                                        ],
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
                AppDialogActions(
                  onConfirm: () => Navigator.pop(ctx, tempSelected),
                  confirmLabel: tempSelected.isEmpty
                      ? 'Xem tất cả'
                      : 'Xem ${tempSelected.length} nhân viên',
                  confirmIcon: Icons.check,
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => _selectedEmployeePins = result);
    }
  }

  /// Danh sách nhân viên duy nhất có chấm công (PIN -> {name, code})
  List<Map<String, String>> get _uniqueEmployees {
    final Map<String, Map<String, String>> seen = {};
    for (final att in _attendances) {
      final pin = att.pin ?? '';
      if (pin.isEmpty || seen.containsKey(pin)) continue;
      seen[pin] = {
        'pin': pin,
        'name': att.employeeName ?? att.deviceUserName ?? 'N/A',
        'code': att.employeeId ?? pin,
      };
    }
    final list = seen.values.toList();
    list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    return list;
  }

  List<Attendance> get _filteredAttendances {
    var list = _attendances;

    // Filter by selected employee PINs
    if (_selectedEmployeePins.isNotEmpty) {
      list = list.where((a) => _selectedEmployeePins.contains(a.pin)).toList();
    }

    // Filter by attendance state (use calculated state)
    if (_filterAttendanceState != null) {
      list = list.where((a) => _getCalculatedState(a) == _filterAttendanceState).toList();
    }

    // Filter by verify mode
    if (_filterVerifyMode != null) {
      list = list.where((a) => a.verifyMode == _filterVerifyMode).toList();
    }

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'pin':
          cmp = (a.pin ?? '').compareTo(b.pin ?? '');
          break;
        case 'name':
          cmp = (a.employeeName ?? '').compareTo(b.employeeName ?? '');
          break;
        case 'state':
          cmp = _getCalculatedState(a).compareTo(_getCalculatedState(b));
          break;
        case 'time':
        default:
          cmp = a.attendanceTime.compareTo(b.attendanceTime);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  String _getDayOfWeek(DateTime date) {
    const days = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    return days[date.weekday % 7];
  }

  Color _getStateColor(int state) {
    switch (state) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.red;
      case 2:
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color _getVerifyColor(int mode) {
    switch (mode) {
      case 1:
        return Colors.indigo;
      case 2:
        return Colors.teal;
      case 15:
      case 9:
        return Colors.purple;
      case 100:
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  IconData _getVerifyIcon(int mode) {
    switch (mode) {
      case 0:
        return Icons.password;
      case 1:
        return Icons.fingerprint;
      case 2:
        return Icons.credit_card;
      case 15:
      case 9:
        return Icons.face;
      case 100:
        return Icons.edit;
      default:
        return Icons.help_outline;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredList = _filteredAttendances;
    final totalPages = (_totalCount / _pageSize).ceil();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Stack(
        children: [
          Column(
            children: [
              // ── Header ──
              _buildHeader(theme),

              // ── Real-time banner ──
              if (_showRealtimeBanner) _buildRealtimeBanner(theme),

              // ── Filter bar ──
              if (!Responsive.isMobile(context) || _showMobileFilters)
                _buildFilterBar(theme),

              // ── Data table ──
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredList.isEmpty
                        ? _buildEmptyState()
                        : _buildDataTable(filteredList, theme),
              ),

              // ── Pagination bar ──
              if (_totalCount > 0 && !Responsive.isMobile(context)) _buildPaginationBar(totalPages, theme),
            ],
          ),

          // ── Sync progress overlay (bottom-right) ──
          if (_activeSyncs.isNotEmpty) _buildSyncProgressOverlay(),
        ],
      ),
    );
  }

  Widget _buildSyncProgressOverlay() {
    return Positioned(
      right: 16,
      bottom: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: _activeSyncs.entries.map((entry) {
          return _buildSyncProgressCard(entry.key, entry.value);
        }).toList(),
      ),
    );
  }

  Widget _buildSyncProgressCard(String syncKey, _SyncProgress sync) {
    Color statusColor;
    IconData statusIcon;
    switch (sync.status) {
      case _SyncStatus.starting:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_top;
        break;
      case _SyncStatus.deleting:
        statusColor = Colors.orange;
        statusIcon = Icons.delete_sweep;
        break;
      case _SyncStatus.syncing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      case _SyncStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case _SyncStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
    }

    return Container(
      width: 320,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sync.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sync.status == _SyncStatus.completed || sync.status == _SyncStatus.error)
                InkWell(
                  onTap: () => setState(() => _activeSyncs.remove(syncKey)),
                  child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sync.message,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (sync.status != _SyncStatus.completed && sync.status != _SyncStatus.error) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: sync.progress > 0 ? sync.progress : null,
                backgroundColor: Colors.grey.shade200,
                color: statusColor,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.access_time_filled, color: Colors.blue.shade700, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chấm công trên máy',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dữ liệu chấm công real-time từ máy chấm công · $_totalCount bản ghi',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Filter toggle (mobile)
          if (Responsive.isMobile(context))
            GestureDetector(
              onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _showMobileFilters ? Colors.blue.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 20, color: Colors.blue.shade700),
                    if (_selectedDeviceId != null || _selectedEmployeePins.isNotEmpty || _selectedPreset != 'today')
                      Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                  ],
                ),
              ),
            ),

          // Export menu
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'excel': _exportToExcel(); break;
                case 'pdf': _exportToPdf(); break;
                case 'png': _exportToPng(); break;
              }
            },
            enabled: !_isExporting,
            tooltip: 'Xuất dữ liệu',
            icon: _isExporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.download, color: Colors.blue.shade700),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 12),
                    const Text('Xuất Excel (.xlsx)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 12),
                    const Text('Xuất PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'png',
                child: Row(
                  children: [
                    Icon(Icons.image, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 12),
                    const Text('Xuất ảnh PNG'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Icon(Icons.fiber_new, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            '${_realtimeQueue.length} bản ghi mới từ máy chấm công',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _showRealtimeBanner = false),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      color: Colors.white,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Device selector
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedDeviceId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Thiết bị',
                prefixIcon: const Icon(Icons.router, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả thiết bị')),
                ..._devices.map((d) => DropdownMenuItem(
                      value: d['id']?.toString(),
                      child: Text(
                        d['deviceName'] ?? d['serialNumber'] ?? 'N/A',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: (val) {
                setState(() => _selectedDeviceId = val);
                _loadAttendances();
              },
            ),
          ),

          // Time preset dropdown
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPreset,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Thời gian',
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
                DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
                DropdownMenuItem(value: 'week', child: Text('Tuần này')),
                DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
                DropdownMenuItem(value: 'month', child: Text('Tháng này')),
                DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
                DropdownMenuItem(value: 'custom', child: Text('Tùy chọn...')),
              ],
              onChanged: (v) async {
                if (v == 'custom') {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
                    locale: const Locale('vi'),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(primary: Theme.of(context).primaryColor),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _fromDate = picked.start;
                      _toDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
                      _selectedPreset = 'custom';
                    });
                    _loadAttendances();
                  }
                } else if (v != null) {
                  _applyPreset(v);
                }
              },
            ),
          ),

          // Date range display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.date_range, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(_fromDate)} - ${DateFormat('dd/MM/yyyy').format(_toDate)}',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 28, color: Colors.grey.shade300),
          const SizedBox(width: 8),

          // Employee multi-select
          InkWell(
            onTap: _showEmployeePickerDialog,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedEmployeePins.isNotEmpty
                      ? Colors.blue.shade400
                      : Colors.grey.shade400,
                ),
                borderRadius: BorderRadius.circular(8),
                color: _selectedEmployeePins.isNotEmpty
                    ? Colors.blue.shade50
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 18,
                    color: _selectedEmployeePins.isNotEmpty
                        ? Colors.blue.shade700
                        : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _selectedEmployeePins.isEmpty
                          ? 'Chọn nhân viên...'
                          : '${_selectedEmployeePins.length} nhân viên',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: _selectedEmployeePins.isNotEmpty
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                        fontWeight: _selectedEmployeePins.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 20,
                    color: Colors.grey.shade600),
                ],
              ),
            ),
          ),

          // Attendance state filter
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int?>(
              initialValue: _filterAttendanceState,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Kiểu chấm',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(value: 0, child: Text('Vào')),
                DropdownMenuItem(value: 1, child: Text('Ra')),
              ],
              onChanged: (val) => setState(() => _filterAttendanceState = val),
            ),
          ),

          // Verify mode filter
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int?>(
              initialValue: _filterVerifyMode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Phương thức',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(value: 0, child: Text('Mật khẩu')),
                DropdownMenuItem(value: 1, child: Text('Vân tay')),
                DropdownMenuItem(value: 2, child: Text('Thẻ')),
                DropdownMenuItem(value: 15, child: Text('Khuôn mặt')),
                DropdownMenuItem(value: 100, child: Text('Thủ công')),
              ],
              onChanged: (val) => setState(() => _filterVerifyMode = val),
            ),
          ),

          // Clear filters
          if (_selectedEmployeePins.isNotEmpty ||
              _filterAttendanceState != null ||
              _filterVerifyMode != null)
            ActionChip(
              label: const Text('Xóa bộ lọc'),
              avatar: const Icon(Icons.clear_all, size: 16),
              onPressed: () {
                setState(() {
                  _selectedEmployeePins = {};
                  _filterAttendanceState = null;
                  _filterVerifyMode = null;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.access_time, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Chưa có dữ liệu chấm công',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Dữ liệu sẽ hiển thị khi nhân viên chấm công trên máy\nhoặc bấm "Tải lại tất cả" để đồng bộ từ thiết bị',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _syncAttendancesFromDevices(),
            icon: const Icon(Icons.sync),
            label: const Text('Đồng bộ dữ liệu'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(List<Attendance> data) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: data.length,
      itemBuilder: (_, index) {
        final att = data[index];
        final isNew = _realtimeQueue.any((r) => r.id == att.id);
        final calcState = _getCalculatedState(att);
        final calcStateText = _getCalculatedStateText(calcState);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isNew ? Colors.green.shade50 : Colors.white,
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
              onTap: () => _showEditAttendanceDialog(att),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isNew ? Colors.green.withValues(alpha: 0.15) : const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.access_time, color: isNew ? Colors.green : const Color(0xFF1E3A5F), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(att.employeeName ?? att.deviceUserName ?? '\u2014', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text([_dateFormat.format(att.attendanceTime), _timeFormat.format(att.attendanceTime), att.deviceName ?? ''].where((s) => s.isNotEmpty).join(' \u00b7 '),
                        style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  _buildStateChip(calcState, calcStateText),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataTable(List<Attendance> data, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildMobileList(data);
        }
        return RepaintBoundary(
          key: _tableKey,
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              color: Colors.black87,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 24,
            horizontalMargin: 16,
            sortColumnIndex: _getSortColumnIndex(),
            sortAscending: _sortAscending,
            columns: [
              const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
              DataColumn(
                label: const Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center)),
                onSort: (_, asc) => _onSort('pin', asc),
              ),
              DataColumn(
                label: const Expanded(child: Text('Tên nhân viên', textAlign: TextAlign.center)),
                onSort: (_, asc) => _onSort('name', asc),
              ),
              const DataColumn(label: Expanded(child: Text('Thiết bị', textAlign: TextAlign.center))),
              DataColumn(
                label: const Expanded(child: Text('Ngày', textAlign: TextAlign.center)),
                onSort: (_, asc) => _onSort('time', asc),
              ),
              const DataColumn(label: Expanded(child: Text('Thứ', textAlign: TextAlign.center))),
              const DataColumn(label: Expanded(child: Text('Giờ chấm', textAlign: TextAlign.center))),
              DataColumn(
                label: const Expanded(child: Text('Kiểu chấm', textAlign: TextAlign.center)),
                onSort: (_, asc) => _onSort('state', asc),
              ),
              const DataColumn(label: Expanded(child: Text('Phương thức', textAlign: TextAlign.center))),
              const DataColumn(label: Expanded(child: Text('Thao tác', textAlign: TextAlign.center))),
            ],
            rows: List.generate(data.length, (index) {
              final att = data[index];
              final isNew = _realtimeQueue.any((r) => r.id == att.id);
              final rowColor = isNew
                  ? Colors.green.shade50
                  : (index % 2 == 0 ? Colors.white : Colors.grey.shade50);
              final calcState = _getCalculatedState(att);
              final calcStateText = _getCalculatedStateText(calcState);

              return DataRow(
                color: WidgetStateProperty.all(rowColor),
                cells: [
                  DataCell(Center(child: Text(
                    '${(_currentPage - 1) * _pageSize + index + 1}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ))),
                  DataCell(Center(child: _buildPinCell(att))),
                  DataCell(Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        att.employeeName ?? att.deviceUserName ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  )),
                  DataCell(Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        att.deviceName ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ),
                  )),
                  DataCell(Center(child: Text(_dateFormat.format(att.attendanceTime)))),
                  DataCell(Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getDayOfWeek(att.attendanceTime),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: att.attendanceTime.weekday >= 6
                              ? Colors.red.shade700
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  )),
                  DataCell(Center(child: Text(
                    _timeFormat.format(att.attendanceTime),
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ))),
                  DataCell(Center(child: _buildStateChip(calcState, calcStateText))),
                  DataCell(Center(child: _buildVerifyChip(att.verifyMode, att.verifyTypeText))),
                  DataCell(Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _showEditAttendanceDialog(att),
                          icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade700),
                          tooltip: 'Sửa giờ chấm',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          onPressed: () => _deleteAttendance(att),
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade600),
                          tooltip: 'Xóa',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  )),
                ],
              );
            }),
          ),
        ),
      ),
      ),
    );
      },
    );
  }

  Widget _buildPinCell(Attendance att) {
    final pin = att.pin ?? '—';
    final code = att.employeeId;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(code ?? pin, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        if (code != null && code != pin)
          Text('PIN: $pin', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildStateChip(int state, String label) {
    final color = _getStateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == 0 ? Icons.login : Icons.logout,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyChip(int mode, String label) {
    final color = _getVerifyColor(mode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getVerifyIcon(mode), size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPaginationBar(int totalPages, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Builder(builder: (context) {
        final isMobile = Responsive.isMobile(context);
        final infoText = Text(
          'Tổng: $_totalCount bản ghi',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        );
        final pageSizeSelector = Row(
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
                  value: _pageSize,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _pageSize = v;
                      _currentPage = 1;
                      _loadAttendances(resetPage: false);
                    }
                  },
                ),
              ),
            ),
          ],
        );
        final pageNav = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _currentPage > 1
                  ? () {
                      _currentPage = 1;
                      _loadAttendances(resetPage: false);
                    }
                  : null,
              icon: const Icon(Icons.first_page, size: 20),
              tooltip: 'Trang đầu',
            ),
            IconButton(
              onPressed: _currentPage > 1
                  ? () {
                      _currentPage--;
                      _loadAttendances(resetPage: false);
                    }
                  : null,
              icon: const Icon(Icons.chevron_left, size: 20),
              tooltip: 'Trang trước',
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Trang $_currentPage / $totalPages',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              onPressed: _currentPage < totalPages
                  ? () {
                      _currentPage++;
                      _loadAttendances(resetPage: false);
                    }
                  : null,
              icon: const Icon(Icons.chevron_right, size: 20),
              tooltip: 'Trang sau',
            ),
            IconButton(
              onPressed: _currentPage < totalPages
                  ? () {
                      _currentPage = totalPages;
                      _loadAttendances(resetPage: false);
                    }
                  : null,
              icon: const Icon(Icons.last_page, size: 20),
              tooltip: 'Trang cuối',
            ),
          ],
        );
        if (isMobile) {
          return Column(children: [infoText, const SizedBox(height: 6), pageSizeSelector, const SizedBox(height: 6), pageNav]);
        }
        return Row(children: [infoText, const SizedBox(width: 16), pageSizeSelector, const Spacer(), pageNav]);
      }),
    );
  }

  int? _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'pin':
        return 1;
      case 'name':
        return 2;
      case 'time':
        return 4;
      case 'state':
        return 7;
      default:
        return null;
    }
  }

  /// Build multi-select delete bar (for future bulk actions)
  // Reserved for later expansion

  void _onSort(String column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
    });
  }
}
