import 'dart:math' as math;
import 'dart:ui' as ui;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../l10n/app_localizations.dart';
import '../models/device.dart';
import '../models/device_user.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_button.dart';
import '../utils/responsive_helper.dart';

// Hàm chuyển đổi tiếng Việt có dấu sang không dấu
String removeVietnameseAccents(String str) {
  const Map<String, String> vietnameseMap = {
    'à': 'a',
    'á': 'a',
    'ả': 'a',
    'ã': 'a',
    'ạ': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'ặ': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'ậ': 'a',
    'đ': 'd',
    'è': 'e',
    'é': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ẹ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ệ': 'e',
    'ì': 'i',
    'í': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ị': 'i',
    'ò': 'o',
    'ó': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ọ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ộ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ợ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ụ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ự': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'ỵ': 'y',
    'À': 'A',
    'Á': 'A',
    'Ả': 'A',
    'Ã': 'A',
    'Ạ': 'A',
    'Ă': 'A',
    'Ằ': 'A',
    'Ắ': 'A',
    'Ẳ': 'A',
    'Ẵ': 'A',
    'Ặ': 'A',
    'Â': 'A',
    'Ầ': 'A',
    'Ấ': 'A',
    'Ẩ': 'A',
    'Ẫ': 'A',
    'Ậ': 'A',
    'Đ': 'D',
    'È': 'E',
    'É': 'E',
    'Ẻ': 'E',
    'Ẽ': 'E',
    'Ẹ': 'E',
    'Ê': 'E',
    'Ề': 'E',
    'Ế': 'E',
    'Ể': 'E',
    'Ễ': 'E',
    'Ệ': 'E',
    'Ì': 'I',
    'Í': 'I',
    'Ỉ': 'I',
    'Ĩ': 'I',
    'Ị': 'I',
    'Ò': 'O',
    'Ó': 'O',
    'Ỏ': 'O',
    'Õ': 'O',
    'Ọ': 'O',
    'Ô': 'O',
    'Ồ': 'O',
    'Ố': 'O',
    'Ổ': 'O',
    'Ỗ': 'O',
    'Ộ': 'O',
    'Ơ': 'O',
    'Ờ': 'O',
    'Ớ': 'O',
    'Ở': 'O',
    'Ỡ': 'O',
    'Ợ': 'O',
    'Ù': 'U',
    'Ú': 'U',
    'Ủ': 'U',
    'Ũ': 'U',
    'Ụ': 'U',
    'Ư': 'U',
    'Ừ': 'U',
    'Ứ': 'U',
    'Ử': 'U',
    'Ữ': 'U',
    'Ự': 'U',
    'Ỳ': 'Y',
    'Ý': 'Y',
    'Ỷ': 'Y',
    'Ỹ': 'Y',
    'Ỵ': 'Y',
  };

  String result = str;
  vietnameseMap.forEach((key, value) {
    result = result.replaceAll(key, value);
  });
  return result;
}

class DeviceUsersScreen extends StatefulWidget {
  const DeviceUsersScreen({super.key});

  @override
  State<DeviceUsersScreen> createState() => _DeviceUsersScreenState();
}

class _DeviceUsersScreenState extends State<DeviceUsersScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final ApiService _apiService = ApiService();
  final GlobalKey _tableKey = GlobalKey();
  List<DeviceUser> _deviceUsers = [];
  List<Device> _devices = [];
  List<Employee> _employees = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _selectedDeviceId;
  String _searchQuery = '';
  int _currentPage = 1;
  int _pageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load devices first - dùng getDevices(storeOnly: true) để lấy thiết bị trong store
      final devicesData = await _apiService.getDevices(storeOnly: true);
      _devices = devicesData.map((e) => Device.fromJson(e)).toList();

      // Load employees for mapping
      final employeesData = await _apiService.getEmployees(pageSize: 500);
      _employees = employeesData.map((e) => Employee.fromJson(e)).toList();

      // Load device users
      await _loadDeviceUsers();
    } catch (e) {
      _showError('Không thể tải dữ liệu: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDeviceUsers() async {
    try {
      // Nếu không chọn device cụ thể, gửi tất cả device IDs
      List<String> deviceIds = [];
      if (_selectedDeviceId != null) {
        deviceIds = [_selectedDeviceId!];
      } else if (_devices.isNotEmpty) {
        deviceIds = _devices.map((d) => d.id).toList();
      }

      final data = await _apiService.getDeviceUsersByDeviceIds(deviceIds);
      if (mounted) {
        setState(() {
          _deviceUsers = data.map((e) => DeviceUser.fromJson(e)).toList();
        });
      }
    } catch (e) {
      _showError('Không thể tải danh sách user: $e');
    }
  }

  Future<void> _downloadUsersFromDevice() async {
    if (_devices.isEmpty) {
      _showError(_l10n.noDeviceConnected);
      return;
    }

    // Show device selection dialog
    final selectedDevice = await showDialog<Device>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.selectDevice),
        content: SizedBox(
          width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn máy để tải danh sách nhân viên:'),
              const SizedBox(height: 16),
              ..._devices.map((device) {
                final isOnline = _isDeviceOnline(device.lastOnline);
                return ListTile(
                  leading: Icon(
                    Icons.router,
                    color: isOnline ? Colors.green : Colors.grey,
                  ),
                  title: Text(device.deviceName),
                  subtitle: Text('SN: ${device.serialNumber}'),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.pop(context, device),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l10n.cancel),
          ),
        ],
      ),
    );

    if (selectedDevice == null) return;
    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Đang gửi lệnh tải nhân viên từ máy...'),
          ],
        ),
      ),
    );

    try {
      // Send command to device to sync users
      final success = await _apiService.sendSyncUsersCommand(selectedDevice.id);
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (success) {
        _showSuccess('Đã gửi lệnh tải nhân viên. Đang chờ dữ liệu từ máy...');

        // Auto reload với retry - đợi máy trả về dữ liệu
        setState(() => _selectedDeviceId = selectedDevice.id);

        // Retry load users nhiều lần trong vòng 30 giây
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(seconds: 5));
          if (!mounted) return;
          await _loadDeviceUsers();
          if (_deviceUsers.isNotEmpty) {
            _showSuccess('Đã tải ${_deviceUsers.length} nhân viên từ máy!');
            return;
          }
        }
        _showSuccess('Lệnh đã gửi. Hãy nhấn Refresh nếu chưa thấy dữ liệu.');
      } else {
        _showError('Không thể gửi lệnh đến máy chấm công');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      _showError('Lỗi: $e');
    }
  }

  bool _isDeviceOnline(DateTime? lastOnline) {
    if (lastOnline == null) return false;
    final diff = DateTime.now().toUtc().difference(lastOnline);
    return diff.inMinutes <= 5;
  }

  Future<void> _uploadEmployeesToDevice() async {
    if (_devices.isEmpty) {
      _showError('Chưa có thiết bị nào được kết nối');
      return;
    }
    if (_employees.isEmpty) {
      _showError('Chưa có hồ sơ nhân sự nào');
      return;
    }

    Device? selectedDevice;
    final selectedEmployees = <Employee>{};
    bool selectAll = false;
    String searchQuery = '';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Filter employees not yet on the selected device
          List<Employee> unlinkedEmployees;
          if (selectedDevice != null) {
            final deviceUsers = _deviceUsers.where((u) => u.deviceId == selectedDevice!.id).toList();
            final existingPins = deviceUsers.map((u) => u.pin).toSet();
            final existingEmployeeIds = deviceUsers
                .where((u) => u.employeeId != null)
                .map((u) => u.employeeId!)
                .toSet();
            unlinkedEmployees = _employees.where((e) {
              return !existingEmployeeIds.contains(e.id) &&
                  !existingPins.contains(e.employeeCode);
            }).toList();
          } else {
            unlinkedEmployees = List.from(_employees);
          }

          final displayEmployees = searchQuery.isEmpty
              ? unlinkedEmployees
              : unlinkedEmployees.where((e) {
                  final q = searchQuery.toLowerCase();
                  return e.fullName.toLowerCase().contains(q) ||
                      e.employeeCode.toLowerCase().contains(q) ||
                      (e.department?.toLowerCase().contains(q) ?? false);
                }).toList();

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.upload, color: Colors.teal),
                SizedBox(width: 8),
                Text('Tải hồ sơ nhân sự xuống máy'),
              ],
            ),
            content: SizedBox(
              width: math.min(600, MediaQuery.of(context).size.width - 32).toDouble(),
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Device selector
                  DropdownButtonFormField<Device>(
                    decoration: const InputDecoration(
                      labelText: 'Chọn thiết bị *',
                      prefixIcon: Icon(Icons.devices),
                      border: OutlineInputBorder(),
                    ),
                    items: _devices.map((d) {
                      final online = _isDeviceOnline(d.lastOnline);
                      return DropdownMenuItem(
                        value: d,
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 10, color: online ? Colors.green : Colors.grey),
                            const SizedBox(width: 8),
                            Text('${d.deviceName} (${d.serialNumber})'),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (d) => setDialogState(() {
                      selectedDevice = d;
                      selectedEmployees.clear();
                      selectAll = false;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          selectedDevice == null
                              ? 'Vui lòng chọn thiết bị để xem nhân viên'
                              : '${unlinkedEmployees.length} nhân viên chưa có trên máy chấm công',
                          style: const TextStyle(fontSize: 13, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm nhân viên...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 8),

                  // Select all
                  Row(
                    children: [
                      Checkbox(
                        value: selectAll,
                        onChanged: (v) {
                          setDialogState(() {
                            selectAll = v ?? false;
                            if (selectAll) {
                              selectedEmployees.addAll(displayEmployees);
                            } else {
                              selectedEmployees.clear();
                            }
                          });
                        },
                      ),
                      Text('Chọn tất cả (${selectedEmployees.length}/${displayEmployees.length})'),
                    ],
                  ),
                  const Divider(height: 24),

                  // Employee list
                  Expanded(
                    child: displayEmployees.isEmpty
                        ? Center(child: Text(
                            selectedDevice == null
                                ? 'Chọn thiết bị để xem danh sách nhân viên'
                                : 'Tất cả nhân viên đã có trên máy chấm công',
                          ))
                        : ListView.builder(
                            itemCount: displayEmployees.length,
                            itemBuilder: (context, index) {
                              final emp = displayEmployees[index];
                              final checked = selectedEmployees.contains(emp);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedEmployees.add(emp);
                                    } else {
                                      selectedEmployees.remove(emp);
                                    }
                                    selectAll = selectedEmployees.length == displayEmployees.length;
                                  });
                                },
                                secondary: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: emp.avatarUrl != null ? NetworkImage(emp.avatarUrl!) : null,
                                  onBackgroundImageError: emp.avatarUrl != null ? (_, __) {} : null,
                                  backgroundColor: Colors.grey[200],
                                  child: emp.avatarUrl == null
                                      ? Text(emp.firstName.isNotEmpty ? emp.firstName[0].toUpperCase() : '?',
                                          style: TextStyle(color: Colors.grey[600]))
                                      : null,
                                ),
                                title: Text(emp.fullName, style: const TextStyle(fontSize: 14)),
                                subtitle: Text(
                                  '${emp.employeeCode}${emp.department != null ? ' • ${emp.department}' : ''}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                onConfirm: selectedDevice != null && selectedEmployees.isNotEmpty
                    ? () => Navigator.pop(context, true)
                    : null,
                confirmLabel: 'Tải ${selectedEmployees.length} nhân viên',
                confirmIcon: Icons.upload,
              ),
            ],
          );
        },
      ),
    );

    if (selectedDevice == null || selectedEmployees.isEmpty) return;

    if (!mounted) return;
    // Show progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text('Đang tải ${selectedEmployees.length} nhân viên xuống máy...')),
          ],
        ),
      ),
    );

    int success = 0;
    int failed = 0;
    final failedNames = <String>[];

    try {
      for (final emp in selectedEmployees) {
        final deviceName = removeVietnameseAccents(emp.fullName);
        final userData = {
          'pin': emp.employeeCode,
          'name': deviceName,
          'privilege': 0,
          'deviceId': selectedDevice!.id,
          'employeeId': emp.id,
          'cardNumber': emp.cardNumber ?? '',
          'password': '',
        };

        try {
          final result = await _apiService.createDeviceUser(userData);
          if (result['isSuccess'] == true) {
            success++;
          } else {
            failed++;
            failedNames.add(emp.fullName);
          }
        } catch (_) {
          failed++;
          failedNames.add(emp.fullName);
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close progress

      if (success > 0) {
        _showSuccess('Đã tải $success nhân viên xuống máy ${selectedDevice!.deviceName}${failed > 0 ? '. $failed thất bại.' : ''}');
        await _loadDeviceUsers();
      } else {
        _showError('Không tải được nhân viên nào. Kiểm tra lại thiết bị.');
      }

      if (failedNames.isNotEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nhân viên tải thất bại'),
            content: SizedBox(
              width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: failedNames.map((n) => ListTile(
                  leading: const Icon(Icons.error, color: Colors.red, size: 18),
                  title: Text(n, style: const TextStyle(fontSize: 13)),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Lỗi: $e');
    }
  }

  List<DeviceUser> get _filteredUsers {
    if (_searchQuery.isEmpty) return _deviceUsers;
    final query = _searchQuery.toLowerCase();
    return _deviceUsers.where((u) {
      return u.name.toLowerCase().contains(query) ||
          u.pin.toLowerCase().contains(query) ||
          (u.cardNumber?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void _showError(String message) {
    if (!mounted) return;
    appNotification.showError(
      title: 'Lỗi',
      message: message,
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    appNotification.showSuccess(
      title: 'Thành công',
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final linkedCount = _deviceUsers.where((u) => u.employeeId != null).length;
    final unlinkedCount = _deviceUsers.length - linkedCount;
    final onlineDevices = _devices.where((d) => _isDeviceOnline(d.lastOnline)).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Gradient header
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return Container(
                padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 14, isMobile ? 16 : 24, 14),
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.fingerprint, size: 22, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _l10n.deviceUsers,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_filteredUsers.length} nhân viên · ${_devices.length} thiết bị',
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                              ),
                            ],
                          ),
                        ),
                        if (!isMobile) ...[
                          _buildHeaderActionBtn(Icons.table_chart_outlined, 'Excel', _isExporting ? null : _exportToExcel),
                          const SizedBox(width: 6),
                          _buildHeaderActionBtn(Icons.image_outlined, 'PNG', _isExporting ? null : _exportToPng),
                          const SizedBox(width: 6),
                          _buildHeaderActionBtn(Icons.download, _l10n.importFromDevice, _downloadUsersFromDevice),
                          const SizedBox(width: 6),
                          _buildHeaderActionBtn(Icons.upload, _l10n.uploadHrProfiles, _uploadEmployeesToDevice),
                          const SizedBox(width: 6),
                          _buildHeaderActionBtn(Icons.person_add, _l10n.addUser, _showAddUserDialog),
                        ],
                      ],
                    ),
                    if (isMobile) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: _showMobileFilters ? 0.25 : 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 16, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(_showMobileFilters ? 'Ẩn lọc' : 'Bộ lọc', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                  if (_selectedDeviceId != null || _searchQuery.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                            _buildHeaderActionBtn(Icons.table_chart_outlined, 'Excel', _isExporting ? null : _exportToExcel),
                            const SizedBox(width: 6),
                            _buildHeaderActionBtn(Icons.image_outlined, 'PNG', _isExporting ? null : _exportToPng),
                            const SizedBox(width: 6),
                            _buildHeaderActionBtn(Icons.download, _l10n.importFromDevice, _downloadUsersFromDevice),
                            const SizedBox(width: 6),
                            _buildHeaderActionBtn(Icons.upload, _l10n.uploadHrProfiles, _uploadEmployeesToDevice),
                            const SizedBox(width: 6),
                            _buildHeaderActionBtn(Icons.person_add, _l10n.addUser, _showAddUserDialog),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  // Stats cards
                  if (Responsive.isMobile(context)) ...[
                    InkWell(
                      onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Tổng quan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                            const Spacer(),
                            Icon(_showMobileSummary ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.blue.shade700),
                          ],
                        ),
                      ),
                    ),
                    if (_showMobileSummary) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatCard(_l10n.totalUsers, '${_deviceUsers.length}', Icons.people_outline, const Color(0xFF1E3A5F)),
                          const SizedBox(width: 10),
                          _buildStatCard(_l10n.linkedUsers, '$linkedCount', Icons.link, const Color(0xFF1E3A5F)),
                          const SizedBox(width: 10),
                          _buildStatCard(_l10n.unlinkedUsers, '$unlinkedCount', Icons.link_off, const Color(0xFFF59E0B)),
                          const SizedBox(width: 10),
                          _buildStatCard(_l10n.onlineDevices, '$onlineDevices/${_devices.length}', Icons.router, const Color(0xFF0F2340)),
                        ],
                      ),
                    ],
                  ] else ...[
                    Row(
                      children: [
                        _buildStatCard(_l10n.totalUsers, '${_deviceUsers.length}', Icons.people_outline, const Color(0xFF1E3A5F)),
                        const SizedBox(width: 10),
                        _buildStatCard(_l10n.linkedUsers, '$linkedCount', Icons.link, const Color(0xFF1E3A5F)),
                        const SizedBox(width: 10),
                        _buildStatCard(_l10n.unlinkedUsers, '$unlinkedCount', Icons.link_off, const Color(0xFFF59E0B)),
                        const SizedBox(width: 10),
                        _buildStatCard(_l10n.onlineDevices, '$onlineDevices/${_devices.length}', Icons.router, const Color(0xFF0F2340)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Filters
                  if (!Responsive.isMobile(context) || _showMobileFilters) ...[
                    _buildFilters(),
                    const SizedBox(height: 12),
                  ],

                  // Content
                  Expanded(
                    child: _isLoading
                        ? const LoadingWidget(message: 'Đang tải...')
                        : _devices.isEmpty
                            ? const EmptyState(
                                icon: Icons.devices,
                                title: 'Chưa có thiết bị',
                                description: 'Hãy kết nối máy chấm công trước',
                              )
                            : _filteredUsers.isEmpty
                                ? EmptyState(
                                    icon: Icons.people,
                                    title: 'Chưa có user',
                                    description: 'Thêm user hoặc đồng bộ từ nhân viên',
                                    actionLabel: _l10n.addUser,
                                    onAction: _showAddUserDialog,
                                  )
                                : _buildUsersList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isFilterMobile = constraints.maxWidth < 600;
          if (isFilterMobile) {
            return Column(
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedDeviceId,
                      isExpanded: true,
                      isDense: true,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.devices, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 6),
                              Text(_l10n.allDevices),
                            ],
                          ),
                        ),
                        ..._devices.map((d) => DropdownMenuItem<String?>(
                          value: d.id,
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 8, color: _isDeviceOnline(d.lastOnline) ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                              const SizedBox(width: 6),
                              Expanded(child: Text('${d.deviceName} (${d.serialNumber})', overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        )),
                      ],
                      selectedItemBuilder: (context) => [
                        Row(
                          children: [
                            Icon(Icons.devices, size: 14, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_l10n.allDevices, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                        ..._devices.map((d) => Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: _isDeviceOnline(d.lastOnline) ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                            const SizedBox(width: 6),
                            Expanded(child: Text('${d.deviceName} (${d.serialNumber})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                          ],
                        )),
                      ],
                      onChanged: (value) async {
                        setState(() => _selectedDeviceId = value);
                        await _loadDeviceUsers();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                        ),
                        child: TextField(
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: _l10n.search,
                            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA1A1AA)),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () => setState(() => _searchQuery = ''),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, color: Theme.of(context).primaryColor, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${_filteredUsers.length}',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(

                  value: _selectedDeviceId,
                  isExpanded: true,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          Icon(Icons.devices, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text(_l10n.allDevices),
                        ],
                      ),
                    ),
                    ..._devices.map((d) => DropdownMenuItem<String?>(
                      value: d.id,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: _isDeviceOnline(d.lastOnline) ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${d.deviceName} (${d.serialNumber})', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )),
                  ],
                  selectedItemBuilder: (context) => [
                    Row(
                      children: [
                        Icon(Icons.devices, size: 14, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_l10n.allDevices, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                    ..._devices.map((d) => Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: _isDeviceOnline(d.lastOnline) ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${d.deviceName} (${d.serialNumber})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      ],
                    )),
                  ],
                  onChanged: (value) async {
                    setState(() => _selectedDeviceId = value);
                    await _loadDeviceUsers();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Search
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: TextField(
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: _l10n.search,
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA1A1AA)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fingerprint, color: Theme.of(context).primaryColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${_filteredUsers.length} user',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
        },
      ),
    );
  }

  Widget _buildUsersList() {
    final allFiltered = _filteredUsers;
    final isMobile = Responsive.isMobile(context);
    final totalPages = (allFiltered.length / _pageSize).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex = isMobile ? 0 : (_currentPage - 1) * _pageSize;
    final endIndex = isMobile ? allFiltered.length : (startIndex + _pageSize).clamp(0, allFiltered.length);
    final displayedUsers = allFiltered.sublist(startIndex, endIndex);

    return Container(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return _buildMobileUserList(displayedUsers);
                }
                return RepaintBoundary(
                  key: _tableKey,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                            dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
                              if (states.contains(WidgetState.hovered)) return const Color(0xFFF1F5F9);
                              return null;
                            }),
                            dividerThickness: 0.5,
                            showCheckboxColumn: false,
                            headingRowHeight: 44,
                            dataRowMinHeight: 42,
                            dataRowMaxHeight: 48,
                            columns: [
                              const DataColumn(label: Expanded(child: Text('Photo', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              const DataColumn(label: Expanded(child: Text('ID', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.privilege, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.deviceName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.nameOnDevice, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.employeeName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.password, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              DataColumn(label: Expanded(child: Text(_l10n.cardCode, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                              const DataColumn(label: Expanded(child: Text('Vân tay', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF71717A))))),
                            ],
                          rows: displayedUsers.asMap().entries.map((entry) {
                            final user = entry.value;
                            final avatarUrl = _getEmployeeAvatarUrl(user);
                            final avatarFullUrl = avatarUrl != null ? _apiService.getFileUrl(avatarUrl) : null;
                            return DataRow(
                              onSelectChanged: (_) => _showUserActionsDialog(user),
                              cells: [
                                DataCell(Center(
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundImage: avatarFullUrl != null ? NetworkImage(avatarFullUrl) : null,
                                    onBackgroundImageError: avatarFullUrl != null ? (_, __) {} : null,
                                    backgroundColor: Colors.grey[200],
                                    child: avatarFullUrl == null
                                        ? Text(
                                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                            style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                )),
                                DataCell(Center(child: Text(user.pin))),
                                DataCell(Center(child: _buildPrivilegeChip(user.privilege))),
                                DataCell(Center(child: Text(user.deviceName ?? '-'))),
                                DataCell(Center(child: Text(user.name))),
                                DataCell(Center(
                                  child: user.employeeName != null
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.link, size: 14, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(_getFullEmployeeName(user), style: const TextStyle(color: Colors.green)),
                                          ],
                                        )
                                      : const Text('-', style: TextStyle(color: Colors.grey)),
                                )),
                                DataCell(Center(child: Text(user.password ?? '-'))),
                                DataCell(Center(child: Text(user.cardNumber ?? '-'))),
                                DataCell(Center(child: Text('${user.fingerprintCount}', style: TextStyle(color: user.fingerprintCount > 0 ? const Color(0xFFEA580C) : Colors.grey)))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
          if (totalPages > 1 && !isMobile) _buildPagination(totalPages, allFiltered.length),
        ],
      ),
      ),
    );
  }

  Widget _buildMobileUserList(List<DeviceUser> users) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: users.length,
      itemBuilder: (_, index) {
        final user = users[index];
        final avatarUrl = _getEmployeeAvatarUrl(user);
        final avatarFullUrl = avatarUrl != null ? _apiService.getFileUrl(avatarUrl) : null;
        return Padding(
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
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showUserActionsDialog(user),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: avatarFullUrl != null ? NetworkImage(avatarFullUrl) : null,
                    onBackgroundImageError: avatarFullUrl != null ? (_, __) {} : null,
                    backgroundColor: Colors.grey[200],
                    child: avatarFullUrl == null
                        ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 14))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.name.isNotEmpty ? user.name : 'User ${user.pin}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text([user.pin, user.deviceName ?? '', user.employeeName ?? 'Ch\u01b0a li\u00ean k\u1ebft'].where((s) => s.isNotEmpty).join(' \u00b7 '),
                        style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.lock_outline, size: 12, color: user.password != null && user.password!.isNotEmpty ? const Color(0xFF16A34A) : const Color(0xFFD4D4D8)),
                        const SizedBox(width: 2),
                        Text('MK', style: TextStyle(fontSize: 10, color: user.password != null && user.password!.isNotEmpty ? const Color(0xFF16A34A) : const Color(0xFFA1A1AA))),
                        const SizedBox(width: 8),
                        Icon(Icons.credit_card, size: 12, color: user.cardNumber != null && user.cardNumber!.isNotEmpty ? const Color(0xFF2563EB) : const Color(0xFFD4D4D8)),
                        const SizedBox(width: 2),
                        Text('Thẻ', style: TextStyle(fontSize: 10, color: user.cardNumber != null && user.cardNumber!.isNotEmpty ? const Color(0xFF2563EB) : const Color(0xFFA1A1AA))),
                        const SizedBox(width: 8),
                        Icon(Icons.fingerprint, size: 12, color: user.fingerprintCount > 0 ? const Color(0xFFEA580C) : const Color(0xFFD4D4D8)),
                        const SizedBox(width: 2),
                        Text('${user.fingerprintCount} vân tay', style: TextStyle(fontSize: 10, color: user.fingerprintCount > 0 ? const Color(0xFFEA580C) : const Color(0xFFA1A1AA))),
                      ]),
                    ]),
                  ),
                  _buildPrivilegeChip(user.privilege),
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

  Widget _buildPagination(int totalPages, int totalItems) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Builder(builder: (context) {
        final isMobile = Responsive.isMobile(context);
        final infoChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Hiển thị ${(_currentPage - 1) * _pageSize + 1}-${(_currentPage * _pageSize).clamp(0, totalItems)} / $totalItems',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF16A34A)),
          ),
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
                    if (v != null) setState(() { _pageSize = v; _currentPage = 1; });
                  },
                ),
              ),
            ),
          ],
        );
        final pageNav = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPageNavBtn(Icons.first_page, _currentPage > 1, () => setState(() => _currentPage = 1)),
            const SizedBox(width: 4),
            _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() => _currentPage--)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_currentPage / $totalPages',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() => _currentPage++)),
            const SizedBox(width: 4),
            _buildPageNavBtn(Icons.last_page, _currentPage < totalPages, () => setState(() => _currentPage = totalPages)),
          ],
        );
        if (isMobile) {
          return Column(children: [infoChip, const SizedBox(height: 8), pageSizeSelector, const SizedBox(height: 8), pageNav]);
        }
        return Row(children: [infoChip, const SizedBox(width: 16), pageSizeSelector, const Spacer(), pageNav]);
      }),
    );
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: enabled ? const Color(0xFF52525B) : const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  void _showUserActionsDialog(DeviceUser user) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final headerWidget = Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : user.pin,
            style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name.isNotEmpty ? user.name : 'User ${user.pin}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                'PIN: ${user.pin} | ${user.privilegeText}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ),
      ],
    );

    final infoCard = Card(
      color: Colors.grey.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildInfoRow(Icons.devices, 'Thiết bị', user.deviceName ?? '-'),
            _buildInfoRow(Icons.credit_card, 'Mã thẻ', user.cardNumber ?? '-'),
            _buildInfoRow(Icons.lock, 'Mật khẩu', user.password ?? '-'),
            _buildInfoRow(
              Icons.person,
              'Liên kết NV',
              user.employeeName ?? 'Chưa liên kết',
              valueColor: user.employeeName != null ? Colors.green : Colors.orange,
            ),
          ],
        ),
      ),
    );

    final actionsList = [
      ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.edit, color: Colors.white, size: 20),
        ),
        title: Text(_l10n.editInfo),
        subtitle: const Text('Sửa tên, mã thẻ, mật khẩu, quyền'),
        onTap: () {
          Navigator.pop(context);
          _showEditUserDialog(user);
        },
      ),
      ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.purple,
          child: Icon(Icons.fingerprint, color: Colors.white, size: 20),
        ),
        title: const Text('Quản lý vân tay'),
        subtitle: const Text('Thêm, xóa dấu vân tay'),
        onTap: () {
          Navigator.pop(context);
          _showFingerprintDialog(user);
        },
      ),
      ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.teal,
          child: Icon(Icons.face, color: Colors.white, size: 20),
        ),
        title: const Text('Quản lý khuôn mặt'),
        subtitle: const Text('Thêm, xóa khuôn mặt'),
        onTap: () {
          Navigator.pop(context);
          _showFaceDialog(user);
        },
      ),
      ListTile(
        leading: CircleAvatar(
          backgroundColor:
              user.employeeId != null ? Colors.green : Colors.orange,
          child: const Icon(Icons.link, color: Colors.white, size: 20),
        ),
        title: Text(user.employeeId != null
            ? 'Đổi liên kết nhân viên'
            : 'Gán với nhân sự'),
        subtitle: Text(user.employeeId != null
            ? 'Đang liên kết: ${user.employeeName}'
            : 'Liên kết với nhân viên trong hệ thống'),
        onTap: () {
          Navigator.pop(context);
          _showLinkEmployeeDialog(user);
        },
      ),
      ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.delete, color: Colors.white, size: 20),
        ),
        title: const Text('Xóa người dùng',
            style: TextStyle(color: Colors.red)),
        subtitle: const Text('Xóa khỏi máy chấm công'),
        onTap: () {
          Navigator.pop(context);
          _confirmDeleteUser(user);
        },
      ),
    ];

    if (isMobile) {
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: Scaffold(
            appBar: AppBar(
              title: Text(user.name.isNotEmpty ? user.name : 'User ${user.pin}'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                headerWidget,
                const SizedBox(height: 16),
                infoCard,
                const SizedBox(height: 16),
                ...actionsList,
              ],
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: headerWidget,
          content: SizedBox(
            width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                infoCard,
                const SizedBox(height: 16),
                ...actionsList,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l10n.cancel),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showFingerprintDialog(DeviceUser user) {
    int? selectedFinger; // Ngón đang chọn
    List<int> enrolledFingers = []; // Danh sách ngón đã đăng ký
    bool isLoading = true;
    bool loadStarted = false; // Tránh gọi API trùng lặp

    final fingerNames = [
      'Ngón cái phải',
      'Ngón trỏ phải',
      'Ngón giữa phải',
      'Ngón áp út phải',
      'Ngón út phải',
      'Ngón cái trái',
      'Ngón trỏ trái',
      'Ngón giữa trái',
      'Ngón áp út trái',
      'Ngón út trái',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Load fingerprints từ DB khi mở dialog
          if (isLoading && !loadStarted) {
            loadStarted = true;
            _apiService.getFingerprints(user.id).then((fingerprints) {
              debugPrint('Loaded fingerprints from DB: $fingerprints');
              if (context.mounted) {
                setDialogState(() {
                  enrolledFingers = fingerprints.map((f) {
                    final index = f['fingerIndex'] ?? f['FingerIndex'];
                    return index as int;
                  }).toList();
                  debugPrint('Enrolled fingers: $enrolledFingers');
                  isLoading = false;
                });
              }
            }).catchError((e) {
              debugPrint('Error loading fingerprints: $e');
              if (context.mounted) {
                setDialogState(() => isLoading = false);
              }
            });
          }

          // Widget cho từng ngón tay - thiết kế mới đẹp hơn
          Widget buildFinger(int index, String shortName,
              {double height = 50, bool isThumb = false}) {
            final isEnrolled = enrolledFingers.contains(index);
            final isSelected = selectedFinger == index;

            return GestureDetector(
              onTap: () => setDialogState(() => selectedFinger = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ngón tay
                    Container(
                      width: isThumb ? 38 : 32,
                      height: height,
                      decoration: BoxDecoration(
                        gradient: isEnrolled
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.green.shade400,
                                  Colors.green.shade600,
                                ],
                              )
                            : LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: isSelected
                                    ? [
                                        Colors.purple.shade300,
                                        Colors.purple.shade500
                                      ]
                                    : [
                                        Colors.grey.shade300,
                                        Colors.grey.shade400
                                      ],
                              ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(isThumb ? 16 : 14),
                          topRight: Radius.circular(isThumb ? 16 : 14),
                          bottomLeft: const Radius.circular(6),
                          bottomRight: const Radius.circular(6),
                        ),
                        border: isSelected
                            ? Border.all(
                                color: Colors.purple.shade700, width: 2.5)
                            : Border.all(
                                color: isEnrolled
                                    ? Colors.green.shade700
                                    : Colors.grey.shade500,
                                width: 1),
                        boxShadow: [
                          if (isSelected) ...[
                            BoxShadow(
                              color: Colors.purple.withValues(alpha: 0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ] else if (isEnrolled) ...[
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Fingerprint icon khi đã đăng ký
                          if (isEnrolled)
                            Icon(
                              Icons.fingerprint,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: isThumb ? 22 : 18,
                            ),
                          // Đường vân tay giả
                          if (!isEnrolled)
                            Positioned(
                              top: 8,
                              child: Column(
                                children: List.generate(
                                    3,
                                    (i) => Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          width: isThumb ? 20 : 16,
                                          height: 1.5,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.purple.shade200
                                                : Colors.grey.shade500
                                                    .withValues(alpha: 0.5),
                                            borderRadius:
                                                BorderRadius.circular(1),
                                          ),
                                        )),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Tên ngón tay
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.purple.withValues(alpha: 0.15)
                            : isEnrolled
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shortName,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.purple.shade700
                              : isEnrolled
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Widget bàn tay
          Widget buildHand(bool isLeftHand) {
            final fingers = isLeftHand
                ? [
                    (index: 9, name: 'Út', height: 40.0, isThumb: false),
                    (index: 8, name: 'Áp út', height: 52.0, isThumb: false),
                    (index: 7, name: 'Giữa', height: 58.0, isThumb: false),
                    (index: 6, name: 'Trỏ', height: 50.0, isThumb: false),
                    (index: 5, name: 'Cái', height: 38.0, isThumb: true),
                  ]
                : [
                    (index: 0, name: 'Cái', height: 38.0, isThumb: true),
                    (index: 1, name: 'Trỏ', height: 50.0, isThumb: false),
                    (index: 2, name: 'Giữa', height: 58.0, isThumb: false),
                    (index: 3, name: 'Áp út', height: 52.0, isThumb: false),
                    (index: 4, name: 'Út', height: 40.0, isThumb: false),
                  ];

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // Label bàn tay
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLeftHand
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLeftHand ? Icons.back_hand : Icons.front_hand,
                          size: 14,
                          color: isLeftHand
                              ? Colors.blue.shade600
                              : Colors.orange.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLeftHand ? 'TAY TRÁI' : 'TAY PHẢI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isLeftHand
                                ? Colors.blue.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Các ngón tay
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: fingers
                        .map((f) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: buildFinger(f.index, f.name,
                                  height: f.height, isThumb: f.isThumb),
                            ))
                        .toList(),
                  ),
                  // Lòng bàn tay
                  const SizedBox(height: 6),
                  Container(
                    width: 150,
                    height: 25,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.grey.shade300, Colors.grey.shade200],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                      border:
                          Border.all(color: Colors.grey.shade400, width: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          final isMobile = MediaQuery.of(context).size.width < 600;

          if (isMobile) {
            // ====== MOBILE: Full-screen dialog, tay trái trên - tay phải dưới ======
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Row(
                    children: [
                      const Icon(Icons.fingerprint, color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vân tay - ${user.name}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                body: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Thống kê
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.fingerprint, color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Đã đăng ký: ${enrolledFingers.length}/10 vân tay',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Hướng dẫn
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Chọn ngón tay → Đăng ký / Xóa',
                                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Chú thích màu
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4))),
                                const SizedBox(width: 4),
                                const Text('Đã đăng ký', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 16),
                                Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
                                const SizedBox(width: 4),
                                const Text('Chưa đăng ký', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Tay trái ở trên
                            buildHand(true),
                            const SizedBox(height: 12),
                            // Tay phải ở dưới
                            buildHand(false),
                            const SizedBox(height: 24),
                            // Hiển thị ngón đang chọn
                            if (selectedFinger != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      fingerNames[selectedFinger!],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      enrolledFingers.contains(selectedFinger) ? 'Đã đăng ký ✓' : 'Chưa đăng ký',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: enrolledFingers.contains(selectedFinger) ? Colors.green : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Nút hành động
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        await _enrollFingerprintAndRefresh(user, selectedFinger!, setDialogState, enrolledFingers);
                                      },
                                      icon: const Icon(Icons.add, size: 18),
                                      label: Text(
                                        enrolledFingers.contains(selectedFinger) ? 'Đăng ký lại' : 'Đăng ký',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.purple,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                  if (enrolledFingers.contains(selectedFinger)) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _deleteSingleFingerprint(user, selectedFinger!, setDialogState, enrolledFingers),
                                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                        label: const Text('Xóa', style: TextStyle(fontSize: 13, color: Colors.red)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            // Nút xóa tất cả
                            if (enrolledFingers.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _deleteAllFingerprints(user),
                                icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 18),
                                label: const Text('Xóa tất cả', style: TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
              ),
            );
          }

          // ====== DESKTOP: AlertDialog, 2 tay cạnh nhau ======
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.fingerprint, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(child: Text('Vân tay - ${user.name}')),
              ],
            ),
            content: isLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Thống kê
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.fingerprint,
                                  color: Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Đã đăng ký: ${enrolledFingers.length}/10 vân tay',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Hướng dẫn
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Chọn ngón tay → Đăng ký / Xóa',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Chú thích màu
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 4),
                            const Text('Đã đăng ký',
                                style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 16),
                            Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 4),
                            const Text('Chưa đăng ký',
                                style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 2 bàn tay cạnh nhau
                        Row(
                          children: [
                            Expanded(child: buildHand(true)), // Tay trái
                            const SizedBox(width: 8),
                            Expanded(child: buildHand(false)), // Tay phải
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Hiển thị ngón đang chọn
                        if (selectedFinger != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.purple.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  fingerNames[selectedFinger!],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.purple),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  enrolledFingers.contains(selectedFinger)
                                      ? 'Đã đăng ký ✓'
                                      : 'Chưa đăng ký',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        enrolledFingers.contains(selectedFinger)
                                            ? Colors.green
                                            : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Nút hành động
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    // Đăng ký vân tay và cập nhật dialog (không đóng)
                                    await _enrollFingerprintAndRefresh(
                                      user,
                                      selectedFinger!,
                                      setDialogState,
                                      enrolledFingers,
                                    );
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(
                                    enrolledFingers.contains(selectedFinger)
                                        ? 'Đăng ký lại'
                                        : 'Đăng ký',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              if (enrolledFingers.contains(selectedFinger)) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _deleteSingleFingerprint(
                                      user,
                                      selectedFinger!,
                                      setDialogState,
                                      enrolledFingers,
                                    ),
                                    icon: const Icon(Icons.delete,
                                        size: 18, color: Colors.red),
                                    label: const Text('Xóa',
                                        style: TextStyle(
                                            fontSize: 13, color: Colors.red)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.red),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Nút xóa tất cả
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (enrolledFingers.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              TextButton.icon(
                                onPressed: () => _deleteAllFingerprints(user),
                                icon: const Icon(Icons.delete_sweep,
                                    color: Colors.red, size: 18),
                                label: const Text('Xóa tất cả',
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSingleFingerprint(DeviceUser user, int fingerIndex,
      StateSetter setDialogState, List<int> enrolledFingers) async {
    final fingerNames = [
      'Ngón cái phải',
      'Ngón trỏ phải',
      'Ngón giữa phải',
      'Ngón áp út phải',
      'Ngón út phải',
      'Ngón cái trái',
      'Ngón trỏ trái',
      'Ngón giữa trái',
      'Ngón áp út trái',
      'Ngón út trái',
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa vân tay ${fingerNames[fingerIndex]}?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _apiService.deleteFingerprint(
        user.deviceId, user.pin, fingerIndex);
    if (success) {
      _showSuccess('Đã gửi lệnh xóa vân tay ${fingerNames[fingerIndex]}');
      setDialogState(() => enrolledFingers.remove(fingerIndex));
    } else {
      _showError('Không thể xóa vân tay');
    }
  }

  /// Đăng ký vân tay và refresh dialog (không đóng dialog chính)
  Future<void> _enrollFingerprintAndRefresh(
    DeviceUser user,
    int fingerIndex,
    StateSetter setDialogState,
    List<int> enrolledFingers,
  ) async {
    // Kiểm tra thiết bị online bằng cách lấy trạng thái mới nhất từ server
    try {
      final freshDevices = await _apiService.getDevices(storeOnly: true);
      final freshDevice = freshDevices.cast<Map<String, dynamic>?>().firstWhere(
        (d) => d!['id'] == user.deviceId,
        orElse: () => null,
      );
      if (freshDevice != null) {
        final lastOnline = freshDevice['lastOnline'] != null
            ? DateTime.tryParse(freshDevice['lastOnline'].toString().endsWith('Z')
                ? freshDevice['lastOnline'].toString()
                : '${freshDevice['lastOnline']}Z')
            : null;
        if (lastOnline != null && !_isDeviceOnline(lastOnline)) {
          _showError('Máy chấm công đang offline. Vui lòng kiểm tra kết nối mạng của thiết bị và thử lại.');
          return;
        }
      }
    } catch (e) {
      debugPrint('Warning: Could not refresh device status: $e');
      // Tiếp tục đăng ký, server sẽ xử lý nếu offline
    }

    final fingerNames = [
      'Ngón cái phải',
      'Ngón trỏ phải',
      'Ngón giữa phải',
      'Ngón áp út phải',
      'Ngón út phải',
      'Ngón cái trái',
      'Ngón trỏ trái',
      'Ngón giữa trái',
      'Ngón áp út trái',
      'Ngón út trái',
    ];

    // Show enrollment progress dialog
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EnrollmentProgressDialog(
        user: user,
        fingerIndex: fingerIndex,
        fingerName: fingerNames[fingerIndex],
        apiService: _apiService,
        isReEnroll: enrolledFingers.contains(fingerIndex),
        onComplete: (success, message) {
          Navigator.pop(dialogContext, success);
          if (success) {
            _showSuccess(message);
          } else {
            _showError(message);
          }
        },
      ),
    );

    // Nếu đăng ký thành công, cập nhật UI ngay lập tức
    if (result == true) {
      // Thêm ngón tay vào danh sách enrolled ngay (đã lưu DB qua EnrollFingerprintStrategy)
      setDialogState(() {
        if (!enrolledFingers.contains(fingerIndex)) {
          enrolledFingers.add(fingerIndex);
        }
        debugPrint('Updated enrolled fingers: $enrolledFingers');
      });
    }
  }

  // ignore: unused_element
  Future<void> _enrollFingerprint(DeviceUser user, int fingerIndex) async {
    final fingerNames = [
      'Ngón cái phải',
      'Ngón trỏ phải',
      'Ngón giữa phải',
      'Ngón áp út phải',
      'Ngón út phải',
      'Ngón cái trái',
      'Ngón trỏ trái',
      'Ngón giữa trái',
      'Ngón áp út trái',
      'Ngón út trái',
    ];

    // Show enrollment progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EnrollmentProgressDialog(
        user: user,
        fingerIndex: fingerIndex,
        fingerName: fingerNames[fingerIndex],
        apiService: _apiService,
        onComplete: (success, message) {
          Navigator.pop(dialogContext);
          if (success) {
            _showSuccess(message);
          } else {
            _showError(message);
          }
        },
      ),
    );
  }

  Future<void> _deleteAllFingerprints(DeviceUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
            'Bạn có chắc chắn muốn xóa tất cả vân tay của "${user.name}"?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;
    Navigator.pop(context); // Close fingerprint dialog

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Đang xóa vân tay...'),
          ],
        ),
      ),
    );

    try {
      final success =
          await _apiService.deleteFingerprint(user.deviceId, user.pin);
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (success) {
        _showSuccess('Đã xóa tất cả vân tay của ${user.name}');
      } else {
        _showError('Không thể xóa vân tay');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Lỗi: $e');
    }
  }

  // ==================== FACE MANAGEMENT ====================

  void _showFaceDialog(DeviceUser user) {
    bool hasFace = false;
    bool isLoading = true;
    bool loadStarted = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading && !loadStarted) {
            loadStarted = true;
            _apiService.getDeviceUserFaces(user.id).then((faces) {
              if (context.mounted) {
                setDialogState(() {
                  hasFace = faces.isNotEmpty;
                  isLoading = false;
                });
              }
            }).catchError((e) {
              debugPrint('Error loading faces: $e');
              if (context.mounted) {
                setDialogState(() => isLoading = false);
              }
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.face, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(child: Text('Khuôn mặt - ${user.name}')),
              ],
            ),
            content: isLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trạng thái khuôn mặt
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: hasFace
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: hasFace
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: hasFace
                                      ? Colors.green.shade50
                                      : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: hasFace
                                        ? Colors.green.shade400
                                        : Colors.grey.shade400,
                                    width: 3,
                                  ),
                                  boxShadow: hasFace
                                      ? [
                                          BoxShadow(
                                            color: Colors.green
                                                .withValues(alpha: 0.3),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  hasFace
                                      ? Icons.face
                                      : Icons.face_outlined,
                                  size: 50,
                                  color: hasFace
                                      ? Colors.green.shade600
                                      : Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                hasFace
                                    ? 'Đã đăng ký khuôn mặt ✓'
                                    : 'Chưa đăng ký khuôn mặt',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: hasFace
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasFace
                                    ? 'Khuôn mặt đã được lưu trên thiết bị'
                                    : 'Chưa có dữ liệu khuôn mặt',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Hướng dẫn
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Giao diện máy chấm công không hỗ trợ mở đăng ký khuôn mặt từ xa. Vui lòng đăng ký trực tiếp trên máy.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Nút đăng ký
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _showFaceNotSupportedMessage();
                            },
                            icon: const Icon(Icons.face, size: 20),
                            label: Text(
                              hasFace ? 'Đăng ký lại khuôn mặt' : 'Đăng ký khuôn mặt',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        if (hasFace) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _deleteDeviceUserFace(
                                user,
                                setDialogState,
                                (val) => hasFace = val,
                              ),
                              icon: const Icon(Icons.delete,
                                  size: 18, color: Colors.red),
                              label: const Text('Xóa khuôn mặt',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Future<void> _enrollFaceAndRefresh(
    DeviceUser user,
    StateSetter setDialogState,
    void Function(bool) setHasFace, {
    bool isReEnroll = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _FaceEnrollmentProgressDialog(
        user: user,
        apiService: _apiService,
        isReEnroll: isReEnroll,
        onComplete: (success, message) {
          Navigator.pop(dialogContext, success);
          if (success) {
            _showSuccess(message);
          } else {
            _showError(message);
          }
        },
      ),
    );

    if (result == true) {
      // Refresh face status
      try {
        List<Map<String, dynamic>> faces = [];
        for (var i = 0; i < 6; i++) {
          await Future.delayed(const Duration(seconds: 2));
          faces = await _apiService.getDeviceUserFaces(user.id);
          if (faces.isNotEmpty) break;
        }
        setDialogState(() {
          setHasFace(faces.isNotEmpty);
        });
      } catch (e) {
        debugPrint('Error refreshing faces: $e');
      }
    }
  }

  Future<void> _showFaceNotSupportedMessage() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Thông báo')),
          ],
        ),
        content: const Text(
          'Giao diện máy chấm công không hỗ trợ. Quý khách vui lòng đăng ký trực tiếp trên máy.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _syncFaceAfterManualEnrollment(
    DeviceUser user,
    StateSetter setDialogState,
    void Function(bool) setHasFace, {
    bool isReEnroll = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isReEnroll ? 'Đăng ký lại khuôn mặt' : 'Đăng ký khuôn mặt',
              ),
            ),
          ],
        ),
        content: Text(
          'Máy FACE 2A/ZAM70 đang mở màn hình đăng ký vân tay khi nhận lệnh khuôn mặt từ xa.\n\nHãy đăng ký khuôn mặt trực tiếp trên máy chấm công cho ${user.name}, sau đó bấm "Đồng bộ ngay" để tải dữ liệu khuôn mặt về hệ thống.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng bộ ngay'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text('Đang gửi lệnh đồng bộ sinh trắc học từ máy...'),
            ),
          ],
        ),
      ),
    );

    try {
      final result = await _apiService.syncBiometrics(user.deviceId);
      if (!mounted) return;
      Navigator.pop(context);

      if (result['isSuccess'] != true) {
        _showError(result['message'] ?? 'Không thể gửi lệnh đồng bộ khuôn mặt');
        return;
      }

      _showSuccess('Đã gửi lệnh đồng bộ. Đang chờ máy trả dữ liệu khuôn mặt...');

      List<Map<String, dynamic>> faces = [];
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 3));
        faces = await _apiService.getDeviceUserFaces(user.id);
        if (faces.isNotEmpty) {
          break;
        }
      }

      setDialogState(() {
        setHasFace(faces.isNotEmpty);
      });

      if (faces.isNotEmpty) {
        _showSuccess('Đã đồng bộ khuôn mặt cho ${user.name}');
      } else {
        _showError('Chưa nhận được dữ liệu khuôn mặt. Hãy đăng ký trực tiếp trên máy rồi thử đồng bộ lại.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Lỗi đồng bộ khuôn mặt: $e');
    }
  }

  Future<void> _deleteDeviceUserFace(
    DeviceUser user,
    StateSetter setDialogState,
    void Function(bool) setHasFace,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa khuôn mặt của "${user.name}"?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _apiService.deleteDeviceUserFace(
        user.deviceId, user.pin);
    if (success) {
      _showSuccess('Đã gửi lệnh xóa khuôn mặt của ${user.name}');
      setDialogState(() {
        setHasFace(false);
      });
    } else {
      _showError('Không thể xóa khuôn mặt');
    }
  }

  String _getFullEmployeeName(DeviceUser user) {
    if (user.employeeId != null) {
      try {
        final emp = _employees.firstWhere((e) => e.id == user.employeeId);
        return emp.fullName;
      } catch (_) {}
    }
    return user.employeeName ?? '-';
  }

  String? _getEmployeeAvatarUrl(DeviceUser user) {
    if (user.employeeId != null) {
      try {
        final emp = _employees.firstWhere((e) => e.id == user.employeeId);
        return emp.avatarUrl;
      } catch (_) {}
    }
    return null;
  }

  // ==================== EXPORT EXCEL / PNG ====================

  Future<void> _exportToExcel() async {
    final data = _filteredUsers;
    if (data.isEmpty) {
      _showError('Không có dữ liệu để xuất');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final excelFile = excel_lib.Excel.createExcel();
      final sheet = excelFile['Nhân sự chấm công'];
      if (excelFile.sheets.containsKey('Sheet1')) {
        excelFile.delete('Sheet1');
      }

      final headerStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#1565C0'),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        fontSize: 11,
      );

      final titleStyle = excel_lib.CellStyle(bold: true, fontSize: 14);
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          excel_lib.TextCellValue('Danh sách nhân sự chấm công');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = titleStyle;
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0));

      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          excel_lib.TextCellValue('${data.length} nhân viên · Xuất lúc ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
          excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1));

      final headers = ['STT', 'ID', 'Quyền', 'Tên thiết bị', 'Tên trong máy', 'Tên nhân viên', 'Mật khẩu', 'Mã thẻ từ'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3));
        cell.value = excel_lib.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      sheet.setColumnWidth(0, 6);
      sheet.setColumnWidth(1, 12);
      sheet.setColumnWidth(2, 15);
      sheet.setColumnWidth(3, 20);
      sheet.setColumnWidth(4, 25);
      sheet.setColumnWidth(5, 25);
      sheet.setColumnWidth(6, 12);
      sheet.setColumnWidth(7, 15);

      final dataCellStyle = excel_lib.CellStyle(fontSize: 11);
      for (int i = 0; i < data.length; i++) {
        final user = data[i];
        final row = i + 4;

        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          ..value = excel_lib.IntCellValue(i + 1)
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.pin)
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.privilege == 14 ? 'Quản trị viên' : 'Người dùng')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.deviceName ?? '-')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.name)
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          ..value = excel_lib.TextCellValue(_getFullEmployeeName(user))
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.password ?? '-')
          ..cellStyle = dataCellStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          ..value = excel_lib.TextCellValue(user.cardNumber ?? '-')
          ..cellStyle = dataCellStyle;
      }

      final bytes = excelFile.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel');

      final fileName = 'NhanSuADMS_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

      if (mounted) {
        _showSuccess('Đã xuất Excel: $fileName (${data.length} nhân viên)');
      }
    } catch (e) {
      _showError('Lỗi xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPng() async {
    final data = _filteredUsers;
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

      final fileName = 'NhanSuADMS_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');

      if (mounted) {
        _showSuccess('Đã xuất ảnh PNG: $fileName');
      }
    } catch (e) {
      _showError('Lỗi xuất PNG: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildPrivilegeChip(int privilege) {
    // ZKTeco chỉ có 2 loại: 0 = Người dùng, 14 = Quản trị viên
    final isAdmin = privilege == 14;
    final text = isAdmin ? 'Admin' : 'User';
    final color = isAdmin ? Colors.red : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  // ignore: unused_element
  Widget _buildUserCard(DeviceUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 28,
              backgroundColor: user.isActive
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : user.pin,
                style: TextStyle(
                  color: user.isActive
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name.isNotEmpty ? user.name : 'User ${user.pin}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildStatusChip(user.isActive),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildInfoChip(Icons.pin, 'PIN: ${user.pin}'),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.security, user.privilegeText),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (user.cardNumber != null &&
                          user.cardNumber!.isNotEmpty)
                        _buildInfoChip(Icons.credit_card, user.cardNumber!),
                      if (user.deviceName != null) ...[
                        const SizedBox(width: 8),
                        _buildInfoChip(Icons.devices, user.deviceName!),
                      ],
                    ],
                  ),
                  if (user.employeeName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.link, size: 14, color: Colors.green[400]),
                        const SizedBox(width: 4),
                        Text(
                          'Liên kết: ${user.employeeName}',
                          style:
                              TextStyle(color: Colors.green[400], fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditUserDialog(user);
                    break;
                  case 'link':
                    _showLinkEmployeeDialog(user);
                    break;
                  case 'delete':
                    _confirmDeleteUser(user);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'link',
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 20, color: Colors.blue),
                      const SizedBox(width: 12),
                      Text(user.employeeId != null
                          ? 'Đổi liên kết NV'
                          : 'Liên kết NV'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Xóa', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive ? Colors.green : Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      ],
    );
  }

  void _showAddUserDialog() {
    if (_devices.isEmpty) {
      _showError('Chưa có thiết bị nào được kết nối');
      return;
    }
    _showUserForm(null);
  }

  void _showEditUserDialog(DeviceUser user) {
    _showUserForm(user);
  }

  void _showUserForm(DeviceUser? user) {
    final isEditing = user != null;
    final pinController = TextEditingController(text: user?.pin);
    final nameController =
        TextEditingController(text: user?.name); // Tên trong máy (không dấu)
    final employeeNameController =
        TextEditingController(); // Tên nhân viên (có dấu)
    final cardController = TextEditingController(text: user?.cardNumber);
    final passwordController = TextEditingController(text: user?.password);
    String? selectedDeviceId =
        user?.deviceId ?? _selectedDeviceId ?? _devices.first.id;
    int selectedPrivilege = user?.privilege ?? 0;
    bool autoGenerateName = true; // Tự động sinh tên không dấu

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Cập nhật tên trong máy khi tên nhân viên thay đổi
          // ignore: unused_element
          void updateDeviceName() {
            if (autoGenerateName && employeeNameController.text.isNotEmpty) {
              nameController.text =
                  removeVietnameseAccents(employeeNameController.text);
            }
          }

          final isMobileForm = Responsive.isMobile(context);

          Widget formFields = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thiết bị
                    DropdownButtonFormField<String>(
                      initialValue: selectedDeviceId,
                      decoration: const InputDecoration(
                        labelText: 'Tên thiết bị *',
                        prefixIcon: Icon(Icons.devices),
                        border: OutlineInputBorder(),
                      ),
                      items: _devices
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(d.deviceName),
                              ))
                          .toList(),
                      onChanged: isEditing
                          ? null
                          : (value) =>
                              setDialogState(() => selectedDeviceId = value),
                    ),
                    const SizedBox(height: 16),

                    // Row 1: PIN và Quyền
                    Row(
                      children: [
                        // PIN/ID máy chấm công - Ẩn đi vì máy sẽ tự cấp khi sync
                        // Nếu muốn hiện lại, bỏ comment phần dưới
                        // Expanded(
                        //   child: TextField(
                        //     controller: pinController,
                        //     decoration: const InputDecoration(
                        //       labelText: 'ID máy chấm công (PIN)',
                        //       prefixIcon: Icon(Icons.pin),
                        //       hintText: 'Để trống sẽ tự sinh',
                        //       border: OutlineInputBorder(),
                        //       helperText: 'Máy chấm công sẽ tự cấp ID khi đồng bộ',
                        //     ),
                        //     enabled: !isEditing,
                        //   ),
                        // ),
                        // const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedPrivilege == 14 ? 14 : 0,
                            decoration: const InputDecoration(
                              labelText: 'Quyền',
                              prefixIcon: Icon(Icons.security),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 0, child: Text('Người dùng')),
                              DropdownMenuItem(
                                  value: 14, child: Text('Quản trị viên')),
                            ],
                            onChanged: (value) => setDialogState(
                                () => selectedPrivilege = value ?? 0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tên nhân viên (có dấu)
                    TextField(
                      controller: employeeNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên nhân viên (có dấu)',
                        prefixIcon: Icon(Icons.person),
                        hintText: 'VD: Nguyễn Văn A',
                        border: OutlineInputBorder(),
                        helperText:
                            'Nhập tên có dấu, sẽ tự động sinh tên không dấu bên dưới',
                      ),
                      onChanged: (value) {
                        if (autoGenerateName) {
                          setDialogState(() {
                            nameController.text =
                                removeVietnameseAccents(value);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Tên trong máy (không dấu) với checkbox tự động
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Tên trong máy (không dấu) *',
                              prefixIcon: Icon(Icons.badge),
                              hintText: 'VD: Nguyen Van A',
                              border: OutlineInputBorder(),
                            ),
                            enabled: !autoGenerateName || isEditing,
                          ),
                        ),
                        if (!isEditing) ...[
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              Checkbox(
                                value: autoGenerateName,
                                onChanged: (value) {
                                  setDialogState(() {
                                    autoGenerateName = value ?? true;
                                    if (autoGenerateName &&
                                        employeeNameController
                                            .text.isNotEmpty) {
                                      nameController.text =
                                          removeVietnameseAccents(
                                              employeeNameController.text);
                                    }
                                  });
                                },
                              ),
                              const Text('Tự động',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 2: Mật khẩu và Mã thẻ từ
                    if (isMobileForm) ...[
                      TextField(
                        controller: passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: cardController,
                        decoration: const InputDecoration(
                          labelText: 'Mã thẻ từ',
                          prefixIcon: Icon(Icons.credit_card),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: passwordController,
                              decoration: const InputDecoration(
                                labelText: 'Mật khẩu',
                                prefixIcon: Icon(Icons.lock),
                                border: OutlineInputBorder(),
                              ),
                              obscureText: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: cardController,
                              decoration: const InputDecoration(
                                labelText: 'Mã thẻ từ',
                                prefixIcon: Icon(Icons.credit_card),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    // Hiển thị UID nếu đang edit
                    if (isEditing) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.fingerprint, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text('UID: ${user.id}',
                                style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ],
                );

          Future<void> onSubmit() async {
            if (nameController.text.isEmpty) {
              _showError('Vui lòng điền Tên trong máy');
              return;
            }

            Navigator.pop(context);
            setState(() => _isLoading = true);

            final data = {
              'pin': pinController.text,
              'name': nameController.text,
              'cardNumber': cardController.text,
              'password': passwordController.text,
              'privilege': selectedPrivilege,
              'deviceId': selectedDeviceId,
            };

            debugPrint('=== CREATE DEVICE USER ===');
            debugPrint('PIN: ${pinController.text} (nếu trống, backend tự sinh)');
            debugPrint('Name: ${nameController.text}');
            debugPrint('CardNumber: ${cardController.text}');
            debugPrint('Privilege: $selectedPrivilege');
            debugPrint('DeviceId: $selectedDeviceId');
            debugPrint('Full data: $data');

            Map<String, dynamic> result;
            if (isEditing) {
              result = await _apiService.updateDeviceUser(user.id, data);
            } else {
              result = await _apiService.createDeviceUser(data);
            }

            if (result['isSuccess'] == true) {
              _showSuccess(isEditing
                  ? 'Đã cập nhật user. Lệnh sẽ gửi đến máy chấm công.'
                  : 'Đã thêm user. ID sẽ được cấp tự động. Vui lòng tải lại để xem ID mới.');
              await _loadDeviceUsers();
            } else {
              _showError(result['message'] ?? 'Không thể lưu user');
            }
            if (mounted) setState(() => _isLoading = false);
          }

          if (isMobileForm) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(isEditing ? 'Chỉnh sửa user' : 'Thêm user mới'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton(
                        onPressed: onSubmit,
                        child: Text(isEditing ? 'Cập nhật' : 'Thêm'),
                      ),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formFields,
                ),
              ),
            );
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            title: Text(isEditing ? 'Chỉnh sửa user' : 'Thêm user mới'),
            content: SizedBox(
              width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
              child: SingleChildScrollView(child: formFields),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_l10n.cancel),
              ),
              ElevatedButton(
                onPressed: onSubmit,
                child: Text(isEditing ? 'Cập nhật' : 'Thêm'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ignore: unused_element
  void _showSyncEmployeeDialog() {
    if (_devices.isEmpty) {
      _showError('Chưa có thiết bị nào được kết nối');
      return;
    }
    if (_employees.isEmpty) {
      _showError('Chưa có nhân viên nào');
      return;
    }

    String? selectedDeviceId = _selectedDeviceId ?? _devices.first.id;
    Employee? selectedEmployee;
    final pinController = TextEditingController();
    final cardController = TextEditingController();
    int selectedPrivilege = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Đồng bộ nhân viên vào máy chấm công'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chọn nhân viên và thiết bị để đồng bộ. User sẽ được tạo trên máy chấm công.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedDeviceId,
                  decoration: const InputDecoration(
                    labelText: 'Thiết bị *',
                    prefixIcon: Icon(Icons.devices),
                  ),
                  items: _devices
                      .map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.deviceName),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedDeviceId = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Employee>(
                  initialValue: selectedEmployee,
                  decoration: const InputDecoration(
                    labelText: 'Chọn nhân viên *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text('${e.fullName} (${e.enrollNumber})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedEmployee = value;
                      if (value != null) {
                        pinController.text = value.enrollNumber;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  decoration: const InputDecoration(
                    labelText: 'PIN trên máy chấm công *',
                    prefixIcon: Icon(Icons.pin),
                    hintText: 'Mã số trên máy chấm công',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cardController,
                  decoration: const InputDecoration(
                    labelText: 'Số thẻ (nếu có)',
                    prefixIcon: Icon(Icons.credit_card),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selectedPrivilege == 14 ? 14 : 0,
                  decoration: const InputDecoration(
                    labelText: 'Quyền hạn',
                    prefixIcon: Icon(Icons.security),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Người dùng')),
                    DropdownMenuItem(value: 14, child: Text('Quản trị viên')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedPrivilege = value ?? 0),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l10n.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (selectedEmployee == null || pinController.text.isEmpty) {
                  _showError('Vui lòng chọn nhân viên và nhập PIN');
                  return;
                }

                Navigator.pop(context);
                setState(() => _isLoading = true);

                // Tạo DeviceUser với thông tin từ Employee
                final data = {
                  'pin': pinController.text,
                  'name': selectedEmployee!.fullName,
                  'cardNumber': cardController.text,
                  'password': '',
                  'privilege': selectedPrivilege,
                  'deviceId': selectedDeviceId,
                };

                final result = await _apiService.createDeviceUser(data);

                if (result['isSuccess'] == true) {
                  // Nếu tạo thành công, liên kết với Employee
                  final deviceUserId = result['data']?['id'];
                  if (deviceUserId != null) {
                    await _apiService.mapDeviceUserToEmployee(
                      deviceUserId.toString(),
                      selectedEmployee!.id,
                    );
                  }
                  _showSuccess(
                      'Đã đồng bộ ${selectedEmployee!.fullName} vào máy chấm công');
                  await _loadDeviceUsers();
                } else {
                  _showError(
                      result['message'] ?? 'Không thể đồng bộ nhân viên');
                }
                if (mounted) setState(() => _isLoading = false);
              },
              icon: const Icon(Icons.sync),
              label: const Text('Đồng bộ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkEmployeeDialog(DeviceUser user) {
    Employee? selectedEmployee;
    if (user.employeeId != null) {
      try {
        selectedEmployee =
            _employees.firstWhere((e) => e.id == user.employeeId);
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Liên kết ${user.name} với nhân viên'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Liên kết user máy chấm công với nhân viên trong hệ thống để theo dõi chấm công.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Employee>(
                initialValue: selectedEmployee,
                decoration: const InputDecoration(
                  labelText: 'Chọn nhân viên',
                  prefixIcon: Icon(Icons.person),
                ),
                items: _employees
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text('${e.fullName} (${e.enrollNumber})'),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedEmployee = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedEmployee == null) {
                  _showError('Vui lòng chọn nhân viên');
                  return;
                }

                Navigator.pop(context);
                setState(() => _isLoading = true);

                final success = await _apiService.mapDeviceUserToEmployee(
                  user.id,
                  selectedEmployee!.id,
                );

                if (success) {
                  _showSuccess('Đã liên kết với ${selectedEmployee!.fullName}');
                  await _loadDeviceUsers();
                } else {
                  _showError('Không thể liên kết');
                }
                if (mounted) setState(() => _isLoading = false);
              },
              child: const Text('Liên kết'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteUser(DeviceUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc muốn xóa "${user.name}" (PIN: ${user.pin})?\n\n'
          'User sẽ bị xóa khỏi máy chấm công.',
        ),
        actions: [
          AppDialogActions.delete(
            onConfirm: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);

              final success = await _apiService.deleteDeviceUser(user.id);

              if (success) {
                _showSuccess('Đã xóa user. Lệnh sẽ gửi đến máy chấm công.');
                await _loadDeviceUsers();
              } else {
                _showError('Không thể xóa user');
              }
              if (mounted) setState(() => _isLoading = false);
            },
          ),
        ],
      ),
    );
  }
}

/// Dialog hiển thị tiến trình đăng ký vân tay
class _EnrollmentProgressDialog extends StatefulWidget {
  final DeviceUser user;
  final int fingerIndex;
  final String fingerName;
  final ApiService apiService;
  final Function(bool success, String message) onComplete;
  final bool isReEnroll;

  const _EnrollmentProgressDialog({
    required this.user,
    required this.fingerIndex,
    required this.fingerName,
    required this.apiService,
    required this.onComplete,
    this.isReEnroll = false,
  });

  @override
  State<_EnrollmentProgressDialog> createState() =>
      _EnrollmentProgressDialogState();
}

class _EnrollmentProgressDialogState extends State<_EnrollmentProgressDialog> {
  String _status = 'sending'; // sending, waiting, scanning, success, error
  String _message = 'Đang gửi lệnh đăng ký...';
  // ignore: unused_field
  int _scanCount = 0; // Số lần quét thành công
  final int _requiredScans = 3; // ZKTeco thường cần 3 lần quét
  String? _commandId;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  Future<void> _startEnrollment() async {
    try {
      // Nếu đăng ký lại ngón đã có, xóa vân tay cũ trên máy trước
      if (widget.isReEnroll) {
        setState(() {
          _message = 'Đang xóa vân tay cũ trên máy...';
        });
        await widget.apiService.deleteFingerprint(
          widget.user.deviceId,
          widget.user.pin,
          widget.fingerIndex,
        );
        // Đợi máy xử lý lệnh xóa
        await Future.delayed(const Duration(seconds: 3));
        if (_isCancelled) return;
        setState(() {
          _message = 'Đang gửi lệnh đăng ký lại...';
        });
      }

      // Gửi lệnh đăng ký
      final result = await widget.apiService.enrollFingerprintWithResponse(
        widget.user.deviceId,
        widget.user.pin,
        widget.fingerIndex,
      );

      if (_isCancelled) return;

      if (result != null && result['isSuccess'] == true) {
        final data = result['data'];
        _commandId = data?['id'];

        setState(() {
          _status = 'waiting';
          _message = 'Đã gửi lệnh.\nVui lòng đặt ngón tay lên máy chấm công.';
        });

        // Bắt đầu polling kiểm tra trạng thái
        _pollCommandStatus();
      } else {
        setState(() {
          _status = 'error';
          _message = 'Không thể gửi lệnh đăng ký vân tay';
        });
      }
    } catch (e) {
      if (_isCancelled) return;
      setState(() {
        _status = 'error';
        _message = 'Lỗi: $e';
      });
    }
  }

  Future<void> _pollCommandStatus() async {
    if (_commandId == null || _isCancelled) return;

    // Poll trong 120 giây (đăng ký vân tay cần nhiều thời gian - 3 lần quét)
    for (int i = 0; i < 60 && !_isCancelled; i++) {
      await Future.delayed(const Duration(seconds: 2));

      if (_isCancelled) return;

      try {
        final status = await widget.apiService.getCommandStatus(_commandId!);

        if (_isCancelled) return;

        if (status != null) {
          final commandStatus =
              status['status']?.toString(); // Backend returns string: Created, Sent, Success, Failed

          if ((commandStatus == 'Sent' || commandStatus == '1') && _status != 'scanning') {
            // Lệnh đã gửi đến máy → máy đang chờ quét vân tay
            setState(() {
              _status = 'scanning';
              _message =
                  'Máy đang chờ quét vân tay...\nĐặt ngón ${widget.fingerName} lên cảm biến.\n(Quét 3 lần theo hướng dẫn trên máy)';
            });
          }

          if (commandStatus == 'Success' || commandStatus == '2') {
            // Backend đã nhận được template từ máy → đăng ký thành công
            setState(() {
              _scanCount = _requiredScans;
              _status = 'success';
              _message = 'Đăng ký vân tay thành công!\n${widget.fingerName}';
            });
            await Future.delayed(const Duration(seconds: 2));
            if (!_isCancelled) {
              widget.onComplete(
                  true, 'Đã đăng ký vân tay ${widget.fingerName} thành công');
            }
            return;
          }

          if (commandStatus == 'Failed' || commandStatus == '3') {
            // Failed
            final errorMsg = status['errorMessage'] as String?;
            final displayError = (errorMsg == null || errorMsg.isEmpty || errorMsg == 'Command executed successfully')
                ? 'Vui lòng đặt ngón tay lên cảm biến và thử lại.'
                : errorMsg;
            setState(() {
              _status = 'error';
              _message = 'Đăng ký thất bại!\n$displayError';
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('Error polling: $e');
      }
    }

    // Timeout — chưa nhận được template từ máy
    if (!_isCancelled && _status != 'success' && _status != 'error') {
      setState(() {
        _status = 'error';
        _message = 'Hết thời gian chờ!\nVui lòng thử lại đăng ký vân tay.';
      });
    }
  }

  void _cancel() {
    _isCancelled = true;
    widget.onComplete(false, 'Đã hủy đăng ký');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _status == 'success'
                ? Icons.check_circle
                : _status == 'error'
                    ? Icons.error
                    : Icons.fingerprint,
            color: _status == 'success'
                ? Colors.green
                : _status == 'error'
                    ? Colors.red
                    : Colors.purple,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Đăng ký vân tay')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hiển thị ngón tay đang đăng ký
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fingerprint, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  widget.fingerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Tiến trình quét
          if (_status == 'scanning') ...[
            // Hiển thị icon vân tay đang chờ quét
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 800),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Icon(
                      Icons.fingerprint,
                      size: 80,
                      color: Colors.purple.withValues(alpha: value),
                    ),
                  ),
                );
              },
              onEnd: () {
                // Trigger rebuild to restart animation
                if (mounted && _status == 'scanning') {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Color(0xFFE0E0E0),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            ),
            const SizedBox(height: 16),
          ] else if (_status == 'success') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_requiredScans, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.green.shade700,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lần ${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
          ],

          // Icon trạng thái
          if (_status == 'sending' || _status == 'waiting')
            const CircularProgressIndicator()
          else if (_status == 'success')
            const Icon(Icons.check_circle, color: Colors.green, size: 60)
          else if (_status == 'error')
            const Icon(Icons.error, color: Colors.red, size: 60)
          else if (_status == 'scanning')
            const SizedBox.shrink(), // Icon đã hiển thị ở trên

          const SizedBox(height: 16),

          // Message
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _status == 'error' ? Colors.red : null,
            ),
          ),

          // Hướng dẫn khi đang chờ quét
          if (_status == 'waiting' || _status == 'scanning') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đặt ngón tay lên máy chấm công\nvà giữ yên cho đến khi hoàn tất.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_status != 'success')
          TextButton(
            onPressed: _cancel,
            child: Text(_status == 'error' ? 'Đóng' : 'Hủy'),
          ),
        if (_status == 'error')
          ElevatedButton(
            onPressed: () {
              setState(() {
                _status = 'sending';
                _message = 'Đang gửi lệnh đăng ký...';
                _scanCount = 0;
                _isCancelled = false;
              });
              _startEnrollment();
            },
            child: const Text('Thử lại'),
          ),
      ],
    );
  }
}

/// Dialog hiển thị tiến trình đăng ký khuôn mặt
class _FaceEnrollmentProgressDialog extends StatefulWidget {
  final DeviceUser user;
  final ApiService apiService;
  final Function(bool success, String message) onComplete;
  final bool isReEnroll;

  const _FaceEnrollmentProgressDialog({
    required this.user,
    required this.apiService,
    required this.onComplete,
    this.isReEnroll = false,
  });

  @override
  State<_FaceEnrollmentProgressDialog> createState() =>
      _FaceEnrollmentProgressDialogState();
}

class _FaceEnrollmentProgressDialogState
    extends State<_FaceEnrollmentProgressDialog> {
  String _status = 'sending';
  String _message = 'Đang gửi lệnh đăng ký khuôn mặt...';
  String? _commandId;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  Future<void> _startEnrollment() async {
    try {
      // Nếu đăng ký lại, xóa khuôn mặt cũ trên máy trước
      if (widget.isReEnroll) {
        setState(() {
          _message = 'Đang xóa khuôn mặt cũ trên máy...';
        });
        await widget.apiService.deleteDeviceUserFace(
          widget.user.deviceId,
          widget.user.pin,
        );
        // Đợi máy xử lý lệnh xóa
        await Future.delayed(const Duration(seconds: 3));
        if (_isCancelled) return;
        setState(() {
          _message = 'Đang gửi lệnh đăng ký lại khuôn mặt...';
        });
      }

      final result = await widget.apiService.enrollFaceWithResponse(
        widget.user.deviceId,
        widget.user.pin,
      );

      if (_isCancelled) return;

      if (result != null && result['isSuccess'] == true) {
        final data = result['data'];
        _commandId = data?['id'];

        setState(() {
          _status = 'waiting';
          _message =
              'Đã gửi lệnh.\nVui lòng nhìn thẳng vào camera trên máy chấm công.';
        });

        _pollCommandStatus();
      } else {
        setState(() {
          _status = 'error';
          _message = 'Không thể gửi lệnh đăng ký khuôn mặt';
        });
      }
    } catch (e) {
      if (_isCancelled) return;
      setState(() {
        _status = 'error';
        _message = 'Lỗi: $e';
      });
    }
  }

  Future<void> _pollCommandStatus() async {
    if (_commandId == null || _isCancelled) return;

    for (int i = 0; i < 60 && !_isCancelled; i++) {
      await Future.delayed(const Duration(seconds: 2));

      if (_isCancelled) return;

      try {
        final status = await widget.apiService.getCommandStatus(_commandId!);

        if (_isCancelled) return;

        if (status != null) {
          final commandStatus = status['status']?.toString();

          if ((commandStatus == 'Sent' || commandStatus == '1') && _status != 'scanning') {
            setState(() {
              _status = 'scanning';
              _message =
                  'Máy đang chờ quét khuôn mặt...\nNhìn thẳng vào camera.';
            });
          }

          if (commandStatus == 'Success' || commandStatus == '2') {
            setState(() {
              _status = 'success';
              _message = 'Đăng ký khuôn mặt thành công!';
            });
            await Future.delayed(const Duration(seconds: 2));
            if (!_isCancelled) {
              widget.onComplete(
                  true, 'Đã đăng ký khuôn mặt cho ${widget.user.name}');
            }
            return;
          }

          if (commandStatus == 'Failed' || commandStatus == '3') {
            final errorMsg = status['errorMessage'] as String?;
            final displayError = (errorMsg == null || errorMsg.isEmpty || errorMsg == 'Command executed successfully')
                ? 'Vui lòng đứng trước camera máy chấm công và thử lại.'
                : errorMsg;
            setState(() {
              _status = 'error';
              _message = 'Đăng ký thất bại!\n$displayError';
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('Error polling face enrollment: $e');
      }
    }

    if (!_isCancelled && _status != 'success' && _status != 'error') {
      setState(() {
        _status = 'error';
        _message = 'Hết thời gian chờ!\nVui lòng thử lại đăng ký khuôn mặt.';
      });
    }
  }

  void _cancel() {
    _isCancelled = true;
    widget.onComplete(false, 'Đã hủy đăng ký');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _status == 'success'
                ? Icons.check_circle
                : _status == 'error'
                    ? Icons.error
                    : Icons.face,
            color: _status == 'success'
                ? Colors.green
                : _status == 'error'
                    ? Colors.red
                    : Colors.teal,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Đăng ký khuôn mặt')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar / Face icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _status == 'success'
                  ? Colors.green.shade50
                  : _status == 'error'
                      ? Colors.red.shade50
                      : Colors.teal.shade50,
              shape: BoxShape.circle,
              border: Border.all(
                color: _status == 'success'
                    ? Colors.green.shade400
                    : _status == 'error'
                        ? Colors.red.shade400
                        : Colors.teal.shade400,
                width: 3,
              ),
            ),
            child: _status == 'sending' || _status == 'waiting'
                ? const CircularProgressIndicator()
                : Icon(
                    _status == 'success'
                        ? Icons.check_circle
                        : _status == 'error'
                            ? Icons.error
                            : Icons.face,
                    size: 50,
                    color: _status == 'success'
                        ? Colors.green
                        : _status == 'error'
                            ? Colors.red
                            : Colors.teal,
                  ),
          ),
          const SizedBox(height: 20),

          // Message
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _status == 'error' ? Colors.red : null,
            ),
          ),

          // Hướng dẫn khi đang chờ quét
          if (_status == 'waiting' || _status == 'scanning') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nhìn thẳng vào camera máy chấm công\nvà giữ yên cho đến khi hoàn tất.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_status != 'success')
          TextButton(
            onPressed: _cancel,
            child: Text(_status == 'error' ? 'Đóng' : 'Hủy'),
          ),
        if (_status == 'error')
          ElevatedButton(
            onPressed: () {
              setState(() {
                _status = 'sending';
                _message = 'Đang gửi lệnh đăng ký khuôn mặt...';
                _isCancelled = false;
              });
              _startEnrollment();
            },
            child: const Text('Thử lại'),
          ),
      ],
    );
  }
}
