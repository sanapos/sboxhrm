import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class RolePermissionsScreen extends StatefulWidget {
  const RolePermissionsScreen({super.key});

  @override
  State<RolePermissionsScreen> createState() => _RolePermissionsScreenState();
}

class _RolePermissionsScreenState extends State<RolePermissionsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _modules = [];
  Map<String, dynamic>? _selectedRolePermissions;
  String? _selectedRoleName;
  bool _isLoading = true;
  bool _isLoadingPermissions = false;
  bool _isSaving = false;

  // Pagination
  int _permPage = 1;
  final int _permPageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getRoles(),
        _apiService.getPermissionModules(),
      ]);
      setState(() {
        _roles = List<Map<String, dynamic>>.from(results[0]);
        _modules = List<Map<String, dynamic>>.from(results[1]);
      });

      // Fallback: if API returns empty, use defaults
      if (_roles.isEmpty) {
        _loadSampleData();
      }
      if (_modules.isEmpty) {
        setState(() => _modules = _getAllModules());
      }
      
      // Auto select first role
      if (_roles.isNotEmpty && _selectedRoleName == null) {
        _selectRole(_roles.first['roleName']);
      }
    } catch (e) {
      // Use sample data
      _loadSampleData();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadSampleData() {
    setState(() {
      _roles = [
        {'roleName': 'Admin', 'roleDisplayName': 'Quản trị viên', 'permissionCount': 42},
        {'roleName': 'Director', 'roleDisplayName': 'Giám đốc', 'permissionCount': 42},
        {'roleName': 'Accountant', 'roleDisplayName': 'Kế toán', 'permissionCount': 42},
        {'roleName': 'DepartmentHead', 'roleDisplayName': 'Trưởng phòng', 'permissionCount': 42},
        {'roleName': 'Manager', 'roleDisplayName': 'Quản lý', 'permissionCount': 42},
        {'roleName': 'Employee', 'roleDisplayName': 'Nhân viên', 'permissionCount': 42},
        {'roleName': 'User', 'roleDisplayName': 'Người dùng', 'permissionCount': 42},
      ];
      _modules = _getAllModules();
    });
  }

  static List<Map<String, dynamic>> _getAllModules() {
    return [
      // ══════════ TỔNG QUAN ══════════
      {'id': '001', 'module': 'Home', 'moduleDisplayName': 'Trang chủ', 'displayOrder': 1},
      {'id': '002', 'module': 'Notification', 'moduleDisplayName': 'Thông báo', 'displayOrder': 2},
      // ══════════ HỒ SƠ NHÂN SỰ ══════════
      {'id': '003', 'module': 'Dashboard', 'moduleDisplayName': 'Tổng quan', 'displayOrder': 3},
      {'id': '004', 'module': 'Employee', 'moduleDisplayName': 'Hồ sơ nhân sự', 'displayOrder': 4},
      {'id': '005', 'module': 'DeviceUser', 'moduleDisplayName': 'Nhân sự chấm công', 'displayOrder': 5},
      {'id': '006', 'module': 'Department', 'moduleDisplayName': 'Phòng ban', 'displayOrder': 6},
      {'id': '007', 'module': 'Leave', 'moduleDisplayName': 'Nghỉ phép', 'displayOrder': 7},
      {'id': '008', 'module': 'SalarySettings', 'moduleDisplayName': 'Thiết lập lương', 'displayOrder': 8},
      // ══════════ CHẤM CÔNG ══════════
      {'id': '009', 'module': 'Attendance', 'moduleDisplayName': 'Chấm công', 'displayOrder': 9},
      {'id': '010', 'module': 'WorkSchedule', 'moduleDisplayName': 'Lịch làm việc', 'displayOrder': 10},
      {'id': '011', 'module': 'AttendanceSummary', 'moduleDisplayName': 'Tổng hợp chấm công', 'displayOrder': 11},
      {'id': '012', 'module': 'AttendanceByShift', 'moduleDisplayName': 'Tổng hợp theo ca', 'displayOrder': 12},
      {'id': '013', 'module': 'AttendanceApproval', 'moduleDisplayName': 'Duyệt chấm công', 'displayOrder': 13},
      {'id': '014', 'module': 'ScheduleApproval', 'moduleDisplayName': 'Duyệt lịch làm việc', 'displayOrder': 14},
      {'id': '015', 'module': 'Payroll', 'moduleDisplayName': 'Tổng hợp lương', 'displayOrder': 15},
      // ══════════ TÀI CHÍNH ══════════
      {'id': '016', 'module': 'BonusPenalty', 'moduleDisplayName': 'Thưởng / Phạt', 'displayOrder': 16},
      {'id': '043', 'module': 'PenaltyTickets', 'moduleDisplayName': 'Phiếu phạt', 'displayOrder': 43},
      {'id': '017', 'module': 'AdvanceRequests', 'moduleDisplayName': 'Ứng lương', 'displayOrder': 17},
      {'id': '018', 'module': 'CashTransaction', 'moduleDisplayName': 'Thu chi', 'displayOrder': 18},
      // ══════════ QUẢN LÝ VẬN HÀNH ══════════
      {'id': '019', 'module': 'Asset', 'moduleDisplayName': 'Tài sản', 'displayOrder': 19},
      {'id': '020', 'module': 'Task', 'moduleDisplayName': 'Công việc', 'displayOrder': 20},
      {'id': '021', 'module': 'Communication', 'moduleDisplayName': 'Truyền thông', 'displayOrder': 21},
      {'id': '022', 'module': 'KPI', 'moduleDisplayName': 'KPI', 'displayOrder': 22},
      {'id': '044', 'module': 'Production', 'moduleDisplayName': 'Sản lượng', 'displayOrder': 43},
      {'id': '045', 'module': 'MobileDeviceRegistration', 'moduleDisplayName': 'Đăng ký chấm công Mobile', 'displayOrder': 46},
      {'id': '046', 'module': 'MobileAttendanceApproval', 'moduleDisplayName': 'Duyệt chấm công Mobile', 'displayOrder': 47},
      {'id': '047', 'module': 'Meal', 'moduleDisplayName': 'Chấm cơm', 'displayOrder': 48},
      {'id': '048', 'module': 'FieldCheckIn', 'moduleDisplayName': 'Check-in điểm bán', 'displayOrder': 49},
      // ══════════ BÁO CÁO ══════════
      {'id': '023', 'module': 'HrReport', 'moduleDisplayName': 'Báo cáo nhân sự', 'displayOrder': 23},
      {'id': '024', 'module': 'AttendanceReport', 'moduleDisplayName': 'Báo cáo chấm công', 'displayOrder': 24},
      {'id': '025', 'module': 'PayrollReport', 'moduleDisplayName': 'Báo cáo lương', 'displayOrder': 25},
      // ══════════ CÀI ĐẶT ══════════
      {'id': '026', 'module': 'SettingsHub', 'moduleDisplayName': 'Thiết lập HRM', 'displayOrder': 26},
      {'id': '027', 'module': 'ShiftSetup', 'moduleDisplayName': 'Thiết lập ca', 'displayOrder': 27},
      {'id': '028', 'module': 'MobileAttendance', 'moduleDisplayName': 'Chấm công mobile', 'displayOrder': 28},
      {'id': '029', 'module': 'Holiday', 'moduleDisplayName': 'Ngày lễ', 'displayOrder': 29},
      {'id': '030', 'module': 'Device', 'moduleDisplayName': 'Máy chấm công', 'displayOrder': 30},
      {'id': '031', 'module': 'Allowance', 'moduleDisplayName': 'Phụ cấp', 'displayOrder': 31},
      {'id': '032', 'module': 'PenaltySetup', 'moduleDisplayName': 'Phạt', 'displayOrder': 32},
      {'id': '033', 'module': 'Insurance', 'moduleDisplayName': 'Bảo hiểm', 'displayOrder': 33},
      {'id': '034', 'module': 'Tax', 'moduleDisplayName': 'Thuế TNCN', 'displayOrder': 34},
      {'id': '049', 'module': 'ProductSalary', 'moduleDisplayName': 'Lương sản phẩm', 'displayOrder': 44},
      {'id': '050', 'module': 'Feedback', 'moduleDisplayName': 'Phản ánh / Ý kiến', 'displayOrder': 45},
      {'id': '035', 'module': 'UserManagement', 'moduleDisplayName': 'Tài khoản', 'displayOrder': 35},
      {'id': '036', 'module': 'Role', 'moduleDisplayName': 'Phân quyền', 'displayOrder': 36},
      {'id': '038', 'module': 'SystemSettings', 'moduleDisplayName': 'Hệ thống', 'displayOrder': 38},
      {'id': '039', 'module': 'NotificationSettings', 'moduleDisplayName': 'Thiết lập thông báo', 'displayOrder': 39},
      {'id': '040', 'module': 'GoogleDrive', 'moduleDisplayName': 'Google Drive', 'displayOrder': 40},
      {'id': '041', 'module': 'AIGemini', 'moduleDisplayName': 'Thiết lập AI', 'displayOrder': 41},
      {'id': '042', 'module': 'Settings', 'moduleDisplayName': 'Cài đặt', 'displayOrder': 42},
    ];
  }

  Future<void> _selectRole(String roleName) async {
    setState(() {
      _selectedRoleName = roleName;
      _isLoadingPermissions = true;
    });

    try {
      // Check if we already have permissions loaded from getRoles() (GET /all)
      final existingRole = _roles.firstWhere(
        (r) => r['roleName'] == roleName && r['permissions'] != null && (r['permissions'] as List).isNotEmpty,
        orElse: () => {},
      );

      if (existingRole.isNotEmpty) {
        setState(() {
          _selectedRolePermissions = Map<String, dynamic>.from(existingRole);
        });
      } else {
        final permissions = await _apiService.getRolePermissions(roleName);
        if (permissions.isNotEmpty && permissions.containsKey('permissions')) {
          setState(() {
            _selectedRolePermissions = Map<String, dynamic>.from(permissions);
          });
        } else {
          _loadSamplePermissions(roleName);
        }
      }
    } catch (e) {
      // Use sample permissions
      _loadSamplePermissions(roleName);
    } finally {
      setState(() => _isLoadingPermissions = false);
    }
  }

  void _loadSamplePermissions(String roleName) {
    final roleDisplay = _roles.firstWhere(
      (r) => r['roleName'] == roleName,
      orElse: () => {'roleDisplayName': roleName},
    )['roleDisplayName'];

    final modules = _modules.isNotEmpty ? _modules : _getAllModules();

    setState(() {
      _selectedRolePermissions = {
        'roleName': roleName,
        'roleDisplayName': roleDisplay,
        'permissions': modules.map((m) {
          final perm = _getDefaultPermission(roleName, m['module'] as String);
          return {
            'permissionId': m['id'],
            'module': m['module'],
            'moduleDisplayName': m['moduleDisplayName'],
            'displayOrder': m['displayOrder'],
            ...perm,
          };
        }).toList(),
      };
    });
  }

  static Map<String, bool> _getDefaultPermission(String roleName, String module) {
    switch (roleName.toLowerCase()) {
      case 'admin':
        return {'canView': true, 'canCreate': true, 'canEdit': true, 'canDelete': true, 'canExport': true, 'canApprove': true};

      case 'director':
        if (['Settings', 'Device', 'Geofence', 'DeviceUser'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        if (['Store', 'Role', 'UserManagement'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': true, 'canApprove': false};
        }
        return {'canView': true, 'canCreate': true, 'canEdit': true, 'canDelete': true, 'canExport': true, 'canApprove': true};

      case 'accountant':
        if (['Salary', 'Payslip', 'Allowance', 'Insurance', 'Tax', 'Advance', 'Transaction', 'CashTransaction', 'BankAccount', 'Benefit'].contains(module)) {
          return {'canView': true, 'canCreate': true, 'canEdit': true, 'canDelete': true, 'canExport': true, 'canApprove': false};
        }
        if (['Report', 'Employee', 'Attendance'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': true, 'canApprove': false};
        }
        if (['Dashboard', 'Leave', 'Shift', 'Holiday', 'Overtime', 'Notification'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        return {'canView': false, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};

      case 'departmenthead':
        if (['Employee', 'Attendance', 'Leave', 'Shift', 'Overtime', 'AttendanceCorrection', 'WorkSchedule', 'ShiftSwap', 'Task', 'KPI', 'HrDocument'].contains(module)) {
          return {'canView': true, 'canCreate': true, 'canEdit': true, 'canDelete': false, 'canExport': true, 'canApprove': true};
        }
        if (['Notification', 'Communication'].contains(module)) {
          return {'canView': true, 'canCreate': true, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        if (['Report', 'Salary', 'Payslip'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': true, 'canApprove': false};
        }
        if (['Dashboard', 'Allowance', 'Holiday', 'Insurance', 'Advance', 'ShiftTemplate', 'ShiftSalaryLevel', 'Benefit', 'Asset', 'OrgChart', 'Department'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        return {'canView': false, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};

      case 'manager':
        if (['Settings', 'Store', 'Role'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        return {'canView': true, 'canCreate': true, 'canEdit': true, 'canDelete': false, 'canExport': true, 'canApprove': true};

      case 'employee':
        if (['Dashboard', 'Attendance', 'Payslip', 'Shift', 'Notification'].contains(module)) {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        if (['Leave', 'ShiftSwap', 'AttendanceCorrection', 'Overtime'].contains(module)) {
          return {'canView': true, 'canCreate': true, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        if (module == 'Task') {
          return {'canView': true, 'canCreate': false, 'canEdit': true, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        return {'canView': false, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};

      case 'user':
        if (module == 'Dashboard') {
          return {'canView': true, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
        }
        return {'canView': false, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};

      default:
        return {'canView': false, 'canCreate': false, 'canEdit': false, 'canDelete': false, 'canExport': false, 'canApprove': false};
    }
  }

  Future<void> _savePermissions() async {
    if (_selectedRolePermissions == null) return;

    setState(() => _isSaving = true);
    try {
      await _apiService.saveRolePermissions(_selectedRolePermissions!);
      appNotification.showSuccess(
        title: 'Thành công',
        message: 'Đã lưu phân quyền cho ${_selectedRolePermissions!['roleDisplayName']}',
      );
      _loadData(); // Reload to update permission count
    } catch (e) {
      appNotification.showError(
        title: 'Lỗi',
        message: 'Không thể lưu phân quyền: $e',
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _togglePermission(int index, String permissionType) {
    if (_selectedRolePermissions == null) return;
    
    setState(() {
      final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions']);
      permissions[index] = Map<String, dynamic>.from(permissions[index]);
      permissions[index][permissionType] = !(permissions[index][permissionType] ?? false);
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _toggleAllForModule(int index, bool value) {
    if (_selectedRolePermissions == null) return;
    
    setState(() {
      final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions']);
      permissions[index] = Map<String, dynamic>.from(permissions[index]);
      permissions[index]['canView'] = value;
      permissions[index]['canCreate'] = value;
      permissions[index]['canEdit'] = value;
      permissions[index]['canDelete'] = value;
      permissions[index]['canExport'] = value;
      permissions[index]['canApprove'] = value;
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _setAllPermissions(String permissionType, bool value) {
    if (_selectedRolePermissions == null) return;
    
    setState(() {
      final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i][permissionType] = value;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  // Chọn tất cả quyền cho role
  void _selectAllPermissions() {
    if (_selectedRolePermissions == null) return;
    
    setState(() {
      final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i]['canView'] = true;
        permissions[i]['canCreate'] = true;
        permissions[i]['canEdit'] = true;
        permissions[i]['canDelete'] = true;
        permissions[i]['canExport'] = true;
        permissions[i]['canApprove'] = true;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  // Bỏ tất cả quyền cho role
  void _deselectAllPermissions() {
    if (_selectedRolePermissions == null) return;
    
    setState(() {
      final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i]['canView'] = false;
        permissions[i]['canCreate'] = false;
        permissions[i]['canEdit'] = false;
        permissions[i]['canDelete'] = false;
        permissions[i]['canExport'] = false;
        permissions[i]['canApprove'] = false;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _showAddRoleDialog() {
    final nameController = TextEditingController();
    final displayNameController = TextEditingController();

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
        title: const Text('Thêm chức danh mới'),
        content: SizedBox(
          width: isMobile ? double.infinity : null,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Mã chức danh',
                hintText: 'VD: Accountant, HRManager...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: 'Tên hiển thị',
                hintText: 'VD: Kế toán, Quản lý nhân sự...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || displayNameController.text.isEmpty) {
                appNotification.showWarning(title: 'Cảnh báo', message: 'Vui lòng nhập đầy đủ thông tin');
                return;
              }
              
              // Check if role already exists
              final exists = _roles.any((r) => r['roleName'] == nameController.text);
              if (exists) {
                appNotification.showWarning(title: 'Cảnh báo', message: 'Chức danh "${nameController.text}" đã tồn tại');
                return;
              }
              
              Navigator.pop(context);
              
              // Save empty permissions to backend to persist the role
              final defaultModules = _getAllModules();
              final permissions = defaultModules.map((m) => {
                'permissionId': m['id'],
                'canView': false,
                'canCreate': false,
                'canEdit': false,
                'canDelete': false,
                'canExport': false,
                'canApprove': false,
              }).toList();
              
              final result = await _apiService.saveRolePermissions({
                'roleName': nameController.text,
                'permissions': permissions,
              });
              
              if (result['isSuccess'] == true || (result['statusCode'] != null && result['statusCode'] < 400)) {
                // Add new role to local list
                setState(() {
                  _roles.add({
                    'roleName': nameController.text,
                    'roleDisplayName': displayNameController.text,
                    'permissionCount': 0,
                  });
                });
                _selectRole(nameController.text);
                appNotification.showSuccess(title: 'Thành công', message: 'Đã tạo chức danh "${displayNameController.text}"');
              } else {
                appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể tạo chức danh');
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRole(String roleName) async {
    final defaultRoles = ['Admin', 'Director', 'Accountant', 'DepartmentHead', 'Manager', 'Employee', 'User'];
    if (defaultRoles.contains(roleName)) {
      appNotification.showWarning(
        title: 'Không thể xóa',
        message: 'Không thể xóa chức danh mặc định của hệ thống',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa chức danh "$roleName" và tất cả quyền liên quan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _apiService.deleteRole(roleName);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã xóa chức danh "$roleName"',
        );
        setState(() {
          _roles.removeWhere((r) => r['roleName'] == roleName);
          if (_selectedRoleName == roleName) {
            _selectedRoleName = null;
            _selectedRolePermissions = null;
          }
        });
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Không thể xóa chức danh',
        );
      }
    } catch (e) {
      appNotification.showError(
        title: 'Lỗi',
        message: 'Không thể xóa chức danh: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Phân quyền Chức danh',
          style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        actions: [
          if (_selectedRolePermissions != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _savePermissions,
                icon: _isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: Text(_isSaving ? 'Đang lưu...' : 'Lưu thay đổi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Responsive.isMobile(context)
              ? _buildMobileBody()
              : Row(
              children: [
                // Left sidebar - Role list
                Container(
                  width: 280,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE4E4E7))),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F2340).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.badge, color: Color(0xFF0F2340), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chức danh',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF18181B),
                                    ),
                                  ),
                                  Text(
                                    'Chọn để phân quyền',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF71717A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _showAddRoleDialog,
                              icon: const Icon(Icons.add_circle, color: Color(0xFF0F2340)),
                              tooltip: 'Thêm chức danh',
                            ),
                          ],
                        ),
                      ),
                      // Role list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _roles.length,
                          itemBuilder: (context, index) {
                            final role = _roles[index];
                            final isSelected = role['roleName'] == _selectedRoleName;
                            return _buildRoleItem(role, isSelected);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Right content - Permissions table
                Expanded(
                  child: _selectedRolePermissions == null
                      ? const Center(
                          child: Text(
                            'Chọn một chức danh để xem và chỉnh sửa quyền',
                            style: TextStyle(color: Color(0xFF71717A)),
                          ),
                        )
                      : _isLoadingPermissions
                          ? const LoadingWidget()
                          : _buildPermissionsTable(),
                ),
              ],
            ),
    );
  }

  // ===== MOBILE BODY =====
  Widget _buildMobileBody() {
    if (_selectedRolePermissions == null) {
      // Step 1: Show role list
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2340).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.badge, color: Color(0xFF0F2340), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chức danh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF18181B))),
                      Text('Chọn để phân quyền', style: TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showAddRoleDialog,
                  icon: const Icon(Icons.add_circle, color: Color(0xFF0F2340)),
                  tooltip: 'Thêm chức danh',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _roles.length,
              itemBuilder: (context, index) {
                final role = _roles[index];
                final isSelected = role['roleName'] == _selectedRoleName;
                return _buildRoleItem(role, isSelected);
              },
            ),
          ),
        ],
      );
    }

    // Step 2: Show permissions for selected role
    final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions'] ?? []);
    return Column(
      children: [
        // Header with back and role info
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
                onPressed: () => setState(() {
                  _selectedRoleName = null;
                  _selectedRolePermissions = null;
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _selectedRolePermissions!['roleDisplayName'] ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _selectAllPermissions,
                icon: const Icon(Icons.check_box, size: 16),
                label: const Text('Tất cả', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              TextButton.icon(
                onPressed: _deselectAllPermissions,
                icon: const Icon(Icons.check_box_outline_blank, size: 16),
                label: const Text('Bỏ', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        // Permissions list as cards
        Expanded(
          child: _isLoadingPermissions
              ? const LoadingWidget()
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: permissions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final perm = permissions[index];
                    final allChecked = (perm['canView'] ?? false) &&
                        (perm['canCreate'] ?? false) &&
                        (perm['canEdit'] ?? false) &&
                        (perm['canDelete'] ?? false) &&
                        (perm['canExport'] ?? false) &&
                        (perm['canApprove'] ?? false);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _getModuleColor(perm['module']).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(_getModuleIcon(perm['module']), size: 16, color: _getModuleColor(perm['module'])),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  perm['moduleDisplayName'] ?? perm['module'],
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              // Toggle all
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(allChecked ? 'Toàn quyền' : '', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                                  Checkbox(
                                    value: allChecked,
                                    onChanged: (value) => _toggleAllForModule(index, value ?? false),
                                    activeColor: const Color(0xFF0F2340),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              _mobilePermChip('Xem', index, 'canView', perm['canView'] ?? false),
                              _mobilePermChip('Thêm', index, 'canCreate', perm['canCreate'] ?? false),
                              _mobilePermChip('Sửa', index, 'canEdit', perm['canEdit'] ?? false),
                              _mobilePermChip('Xóa', index, 'canDelete', perm['canDelete'] ?? false),
                              _mobilePermChip('Xuất', index, 'canExport', perm['canExport'] ?? false),
                              _mobilePermChip('Duyệt', index, 'canApprove', perm['canApprove'] ?? false),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _mobilePermChip(String label, int index, String permType, bool value) {
    return GestureDetector(
      onTap: () => _togglePermission(index, permType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? _getPermissionColor(permType).withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value ? _getPermissionColor(permType).withValues(alpha: 0.3) : const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 14,
              color: value ? _getPermissionColor(permType) : const Color(0xFFA1A1AA),
            ),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: value ? _getPermissionColor(permType) : const Color(0xFF71717A))),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleItem(Map<String, dynamic> role, bool isSelected) {
    final permissions = role['permissions'] as List?;
    final permCount = permissions != null
        ? permissions.where((p) => p['canView'] == true).length
        : (role['permissionCount'] ?? 0);
    final defaultRoles = ['Admin', 'Director', 'Accountant', 'DepartmentHead', 'Manager', 'Employee', 'User'];
    final canDelete = !defaultRoles.contains(role['roleName']);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF0F2340).withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? const Color(0xFF0F2340) : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: () => _selectRole(role['roleName']),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getRoleColor(role['roleName']).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getRoleIcon(role['roleName']),
            color: _getRoleColor(role['roleName']),
            size: 20,
          ),
        ),
        title: Text(
          role['roleDisplayName'] ?? role['roleName'],
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F2340) : const Color(0xFF18181B),
          ),
        ),
        subtitle: Text(
          '$permCount module được cấp quyền',
          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF0F2340), size: 20),
            if (canDelete)
              IconButton(
                onPressed: () => _deleteRole(role['roleName']),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: const Color(0xFFEF4444),
                tooltip: 'Xóa chức danh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsTable() {
    final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions'] ?? []);
    
    return Column(
      children: [
        // Header with role info
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _getRoleColor(_selectedRoleName ?? ''),
                      _getRoleColor(_selectedRoleName ?? '').withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getRoleIcon(_selectedRoleName ?? ''),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phân quyền cho: ${_selectedRolePermissions!['roleDisplayName']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      'Tick vào ô để cấp/bỏ quyền. Thay đổi sẽ được lưu khi bấm "Lưu thay đổi"',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Quick select buttons
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectAllPermissions,
                      icon: const Icon(Icons.check_box, size: 18),
                      label: const Text('Chọn tất cả'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(color: Color(0xFF1E3A5F)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _deselectAllPermissions,
                      icon: const Icon(Icons.check_box_outline_blank, size: 18),
                      label: const Text('Bỏ tất cả'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Permissions table
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 200,
                          child: Text(
                            'Chức năng',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF52525B)),
                          ),
                        ),
                        _buildHeaderCheckbox('Xem danh sách', 'canView'),
                        _buildHeaderCheckbox('Thêm mới', 'canCreate'),
                        _buildHeaderCheckbox('Chỉnh sửa', 'canEdit'),
                        _buildHeaderCheckbox('Xóa', 'canDelete'),
                        _buildHeaderCheckbox('Xuất Excel', 'canExport'),
                        _buildHeaderCheckbox('Phê duyệt', 'canApprove'),
                        const SizedBox(width: 90, child: Text('Toàn quyền', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF52525B)))),
                      ],
                    ),
                  ),
                  // Table rows - paginated
                  Builder(builder: (_) {
                    final totalPages = (permissions.length / _permPageSize).ceil();
                    final safePage = _permPage.clamp(1, totalPages == 0 ? 1 : totalPages);
                    final startIdx = (safePage - 1) * _permPageSize;
                    final endIdx = (startIdx + _permPageSize).clamp(0, permissions.length);
                    final pagePerms = permissions.sublist(startIdx, endIdx);
                    return Column(children: [
                    ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pagePerms.length,
                    separatorBuilder: (_, __) => const Divider(height: 24, color: Color(0xFFE4E4E7)),
                    itemBuilder: (context, index) {
                      final globalIndex = startIdx + index;
                      final perm = pagePerms[index];
                      final allChecked = (perm['canView'] ?? false) &&
                          (perm['canCreate'] ?? false) &&
                          (perm['canEdit'] ?? false) &&
                          (perm['canDelete'] ?? false) &&
                          (perm['canExport'] ?? false) &&
                          (perm['canApprove'] ?? false);
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: index % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 200,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _getModuleColor(perm['module']).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      _getModuleIcon(perm['module']),
                                      size: 16,
                                      color: _getModuleColor(perm['module']),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      perm['moduleDisplayName'] ?? perm['module'],
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildPermissionCheckbox(globalIndex, 'canView', perm['canView'] ?? false),
                            _buildPermissionCheckbox(globalIndex, 'canCreate', perm['canCreate'] ?? false),
                            _buildPermissionCheckbox(globalIndex, 'canEdit', perm['canEdit'] ?? false),
                            _buildPermissionCheckbox(globalIndex, 'canDelete', perm['canDelete'] ?? false),
                            _buildPermissionCheckbox(globalIndex, 'canExport', perm['canExport'] ?? false),
                            _buildPermissionCheckbox(globalIndex, 'canApprove', perm['canApprove'] ?? false),
                            SizedBox(
                              width: 90,
                              child: Center(
                                child: Checkbox(
                                  value: allChecked,
                                  onChanged: (value) => _toggleAllForModule(globalIndex, value ?? false),
                                  activeColor: const Color(0xFF0F2340),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                    if (totalPages > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(icon: const Icon(Icons.first_page), onPressed: safePage > 1 ? () => setState(() => _permPage = 1) : null),
                            IconButton(icon: const Icon(Icons.chevron_left), onPressed: safePage > 1 ? () => setState(() => _permPage--) : null),
                            Text('Trang $safePage / $totalPages (${permissions.length} dòng)', style: const TextStyle(fontSize: 13)),
                            IconButton(icon: const Icon(Icons.chevron_right), onPressed: safePage < totalPages ? () => setState(() => _permPage++) : null),
                            IconButton(icon: const Icon(Icons.last_page), onPressed: safePage < totalPages ? () => setState(() => _permPage = totalPages) : null),
                          ],
                        ),
                      ),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCheckbox(String label, String permissionType) {
    return SizedBox(
      width: 100,
      child: InkWell(
        onTap: () {
          // Check if all are selected
          final permissions = List<Map<String, dynamic>>.from(_selectedRolePermissions!['permissions'] ?? []);
          final allSelected = permissions.every((p) => p[permissionType] == true);
          _setAllPermissions(permissionType, !allSelected);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF52525B), fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.unfold_more, size: 14, color: Color(0xFFA1A1AA)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCheckbox(int index, String permissionType, bool value) {
    return SizedBox(
      width: 100,
      child: Center(
        child: Checkbox(
          value: value,
          onChanged: (_) => _togglePermission(index, permissionType),
          activeColor: _getPermissionColor(permissionType),
        ),
      ),
    );
  }

  Color _getRoleColor(String roleName) {
    switch (roleName) {
      case 'Admin':
        return const Color(0xFFEF4444);
      case 'Director':
        return const Color(0xFFD97706);
      case 'Accountant':
        return const Color(0xFF1E3A5F);
      case 'DepartmentHead':
        return const Color(0xFF1E3A5F);
      case 'Manager':
        return const Color(0xFF0F2340);
      case 'Employee':
        return const Color(0xFF1E3A5F);
      case 'User':
        return const Color(0xFF71717A);
      default:
        return const Color(0xFF71717A);
    }
  }

  IconData _getRoleIcon(String roleName) {
    switch (roleName) {
      case 'Admin':
        return Icons.admin_panel_settings;
      case 'Director':
        return Icons.business_center;
      case 'Accountant':
        return Icons.calculate;
      case 'DepartmentHead':
        return Icons.groups;
      case 'Manager':
        return Icons.supervisor_account;
      case 'Employee':
        return Icons.person;
      case 'User':
        return Icons.person_outline;
      default:
        return Icons.badge;
    }
  }

  Color _getModuleColor(String? module) {
    switch (module) {
      case 'Dashboard':
        return const Color(0xFF1E3A5F);
      case 'Employee':
        return const Color(0xFF0F2340);
      case 'Attendance':
        return const Color(0xFFF59E0B);
      case 'Leave':
        return const Color(0xFF1E3A5F);
      case 'Salary':
      case 'Payslip':
        return const Color(0xFF1E3A5F);
      case 'Device':
        return const Color(0xFFEC4899);
      case 'Report':
        return const Color(0xFF2D5F8B);
      case 'Settings':
        return const Color(0xFF71717A);
      default:
        return const Color(0xFF71717A);
    }
  }

  IconData _getModuleIcon(String? module) {
    switch (module) {
      case 'Dashboard':
        return Icons.dashboard;
      case 'Employee':
        return Icons.people;
      case 'Attendance':
        return Icons.fingerprint;
      case 'Leave':
        return Icons.event_busy;
      case 'Shift':
        return Icons.schedule;
      case 'Salary':
        return Icons.attach_money;
      case 'Payslip':
        return Icons.receipt_long;
      case 'Device':
        return Icons.devices;
      case 'Report':
        return Icons.assessment;
      case 'Settings':
        return Icons.settings;
      case 'Account':
        return Icons.manage_accounts;
      case 'Role':
        return Icons.security;
      case 'Store':
        return Icons.store;
      case 'Allowance':
        return Icons.card_giftcard;
      case 'Holiday':
        return Icons.celebration;
      case 'Insurance':
        return Icons.health_and_safety;
      case 'Tax':
        return Icons.receipt;
      case 'Advance':
        return Icons.money;
      case 'Notification':
        return Icons.notifications;
      default:
        return Icons.folder;
    }
  }

  Color _getPermissionColor(String permissionType) {
    switch (permissionType) {
      case 'canView':
        return const Color(0xFF1E3A5F);
      case 'canCreate':
        return const Color(0xFF1E3A5F);
      case 'canEdit':
        return const Color(0xFFF59E0B);
      case 'canDelete':
        return const Color(0xFFEF4444);
      case 'canExport':
        return const Color(0xFF0F2340);
      case 'canApprove':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF71717A);
    }
  }
}
