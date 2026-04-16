// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import '../utils/file_saver.dart' as file_saver;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/employee.dart';
import '../models/department.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_button.dart';
import 'main_layout.dart';
import '../l10n/app_localizations.dart';
import '../utils/image_source_picker.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  PermissionProvider get _perm => Provider.of<PermissionProvider>(context, listen: false);
  static const _module = 'Employee';
  final ApiService _apiService = ApiService();
  List<Employee> _employees = [];
  List<Employee> _filteredEmployees = [];
  bool _isLoading = true;
  bool _isEmployee = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String _searchQuery = '';
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];
  String _filterDepartment = 'Tất cả';
  String _filterStatus = 'Tất cả';

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;
  List<String> _departments = ['Tất cả'];
  List<String> _positions = [];
  List<Department> _departmentList = [];
  Map<String, List<String>> _departmentPositions = {};

  final List<String> _vietnamBanks = [
    'Vietcombank - NH TMCP Ngoại thương Việt Nam',
    'VietinBank - NH TMCP Công thương Việt Nam',
    'BIDV - NH TMCP Đầu tư và Phát triển Việt Nam',
    'Agribank - NH Nông nghiệp và Phát triển Nông thôn',
    'Techcombank - NH TMCP Kỹ thương Việt Nam',
    'MB Bank - NH TMCP Quân đội',
    'ACB - NH TMCP Á Châu',
    'VPBank - NH TMCP Việt Nam Thịnh Vượng',
    'Sacombank - NH TMCP Sài Gòn Thương Tín',
    'TPBank - NH TMCP Tiên Phong',
    'HDBank - NH TMCP Phát triển TP.HCM',
    'SHB - NH TMCP Sài Gòn - Hà Nội',
    'VIB - NH TMCP Quốc tế Việt Nam',
    'SeABank - NH TMCP Đông Nam Á',
    'MSB - NH TMCP Hàng Hải Việt Nam',
    'Eximbank - NH TMCP Xuất Nhập khẩu Việt Nam',
    'LienVietPostBank - NH TMCP Bưu điện Liên Việt',
    'OCB - NH TMCP Phương Đông',
    'Nam A Bank - NH TMCP Nam Á',
    'Bac A Bank - NH TMCP Bắc Á',
    'PVcomBank - NH TMCP Đại chúng Việt Nam',
    'VietABank - NH TMCP Việt Á',
    'SCB - NH TMCP Sài Gòn',
    'Kienlongbank - NH TMCP Kiên Long',
    'ABBank - NH TMCP An Bình',
    'NCB - NH TMCP Quốc dân',
    'Saigonbank - NH TMCP Sài Gòn Công Thương',
    'BaoVietBank - NH TMCP Bảo Việt',
    'VietBank - NH TMCP Việt Nam Thương Tín',
    'GPBank - NH TMCP Dầu khí Toàn cầu',
    'CIMB Bank Vietnam',
    'UOB Vietnam',
    'HSBC Vietnam',
    'Standard Chartered Vietnam',
    'Shinhan Bank Vietnam',
    'Woori Bank Vietnam',
  ];

  // 34 tỉnh thành Việt Nam sau sáp nhập 2025
  static const List<String> _vietnamProvinces = [
    'Hà Nội', // Hà Nội + Hoà Bình + Vĩnh Phúc
    'TP. Hồ Chí Minh', // TP.HCM + Bình Dương
    'Hải Phòng', // Hải Phòng + Hải Dương + Hưng Yên
    'Đà Nẵng', // Đà Nẵng + Quảng Nam
    'Huế', // Thừa Thiên Huế
    'Cần Thơ', // Cần Thơ + Hậu Giang
    'Quảng Ninh', // Quảng Ninh + Lạng Sơn
    'Thái Nguyên', // Thái Nguyên + Bắc Kạn + Cao Bằng
    'Bắc Ninh', // Bắc Ninh + Bắc Giang
    'Lào Cai', // Lào Cai + Hà Giang + Tuyên Quang
    'Yên Bái', // Yên Bái + Phú Thọ
    'Điện Biên', // Điện Biên + Lai Châu
    'Sơn La', // Sơn La
    'Nam Định', // Nam Định + Ninh Bình + Thái Bình + Hà Nam
    'Thanh Hóa', // Thanh Hóa
    'Nghệ An', // Nghệ An + Hà Tĩnh
    'Quảng Bình', // Quảng Bình + Quảng Trị
    'Quảng Ngãi', // Quảng Ngãi + Bình Định
    'Phú Yên', // Phú Yên + Khánh Hòa
    'Gia Lai', // Gia Lai + Kon Tum
    'Đắk Lắk', // Đắk Lắk + Đắk Nông
    'Lâm Đồng', // Lâm Đồng + Ninh Thuận + Bình Thuận
    'Đồng Nai', // Đồng Nai + Bà Rịa - Vũng Tàu
    'Tây Ninh', // Tây Ninh + Bình Phước
    'Long An', // Long An + Tiền Giang
    'Đồng Tháp', // Đồng Tháp + An Giang
    'Vĩnh Long', // Vĩnh Long + Trà Vinh + Bến Tre
    'Sóc Trăng', // Sóc Trăng + Bạc Liêu
    'Cà Mau',
    'Kiên Giang',
    'Bắc Giang', // (nếu tách riêng khỏi Bắc Ninh)
    'Phú Thọ', // (nếu tách riêng khỏi Yên Bái)
    'Hà Tĩnh', // (nếu tách riêng khỏi Nghệ An)
    'Bình Định', // (nếu tách riêng khỏi Quảng Ngãi)
  ];

  final List<String> _statuses = [
    'Tất cả',
    'Đang làm việc',
    'Đang thử việc',
    'Nghỉ phép',
    'Đã nghỉ việc',
  ];

  final List<String> _genders = ['Nam', 'Nữ', 'Khác'];
  final List<String> _maritalStatuses = [
    'Độc thân',
    'Đã kết hôn',
    'Ly hôn',
    'Góa'
  ];

  // Helper function to remove Vietnamese accents
  String _removeVietnameseAccents(String str) {
    const vietnamese =
        'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ';
    const nonVietnamese =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    String result = str;
    for (int i = 0; i < vietnamese.length; i++) {
      result = result.replaceAll(vietnamese[i], nonVietnamese[i]);
    }
    return result;
  }

  /// Parse Vietnamese CCCD QR code data
  /// Format: CCCD|CMND_CU|HO_TEN|NGAY_SINH|GIOI_TINH|DIA_CHI|NGAY_CAP
  /// Example: 012345678901|123456789|NGUYEN VAN A|19900101|Nam|Hanoi|20220101
  /// Some QR codes may have fewer fields (no old CMND): CCCD|HO_TEN|NGAY_SINH|GIOI_TINH|DIA_CHI|NGAY_CAP
  Map<String, dynamic>? _parseCccdQr(String raw) {
    final parts = raw.split('|');
    if (parts.length < 6) return null;

    // Determine format: 7 fields = has old CMND, 6 fields = no old CMND
    String? cccd;
    String? fullName;
    String? dobStr;
    String? gender;
    String? address;
    String? issueDateStr;

    if (parts.length >= 7) {
      // 7-field format: CCCD|CMND_CU|HO_TEN|NGAY_SINH|GIOI_TINH|DIA_CHI|NGAY_CAP
      cccd = parts[0].trim();
      // parts[1] = old CMND (ignored for now)
      fullName = parts[2].trim();
      dobStr = parts[3].trim();
      gender = parts[4].trim();
      address = parts[5].trim();
      issueDateStr = parts[6].trim();
    } else {
      // 6-field format: CCCD|HO_TEN|NGAY_SINH|GIOI_TINH|DIA_CHI|NGAY_CAP
      cccd = parts[0].trim();
      fullName = parts[1].trim();
      dobStr = parts[2].trim();
      gender = parts[3].trim();
      address = parts[4].trim();
      issueDateStr = parts[5].trim();
    }

    // Validate CCCD is 12 digits
    if (cccd.length != 12 || int.tryParse(cccd) == null) return null;

    // Parse date of birth (ddMMyyyy → DateTime)
    // Vietnamese CCCD QR uses ddMMyyyy format (e.g. 01011990 = 01/01/1990)
    DateTime? dob;
    if (dobStr.length == 8) {
      final d = int.tryParse(dobStr.substring(0, 2));
      final m = int.tryParse(dobStr.substring(2, 4));
      final y = int.tryParse(dobStr.substring(4, 8));
      if (y != null && m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        dob = DateTime(y, m, d);
      }
    } else if (dobStr.contains('/')) {
      try {
        dob = DateFormat('dd/MM/yyyy').parse(dobStr);
      } catch (_) {}
    }

    // Normalize gender
    String? genderNormalized;
    final genderLower = gender.toLowerCase();
    if (genderLower == 'nam' || genderLower == 'male') {
      genderNormalized = 'Nam';
    } else if (genderLower == 'nữ' ||
        genderLower == 'nu' ||
        genderLower == 'female') {
      genderNormalized = 'Nữ';
    }

    // Convert fullName to title case
    final nameFormatted = fullName.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');

    // Extract province from address for hometown field
    String? province = _extractProvinceFromAddress(address);

    return {
      'cccd': cccd,
      'fullName': nameFormatted,
      'dob': dob,
      'gender': genderNormalized,
      'address': address,
      'issueDate': issueDateStr,
      'province': province,
    };
  }

  /// Extract province/city from CCCD address string
  /// CCCD address format: "Xã ABC, Huyện XYZ, Tỉnh Nghệ An"
  static String? _extractProvinceFromAddress(String address) {
    if (address.isEmpty) return null;
    final lowerAddr = address.toLowerCase();

    // Map of alternate/full names that CCCD may use → province in _vietnamProvinces
    const cccdToProvince = <String, String>{
      'thừa thiên huế': 'Huế',
      'thua thien hue': 'Huế',
      'tp hồ chí minh': 'TP. Hồ Chí Minh',
      'tp. hồ chí minh': 'TP. Hồ Chí Minh',
      'thành phố hồ chí minh': 'TP. Hồ Chí Minh',
      'hồ chí minh': 'TP. Hồ Chí Minh',
      'ho chi minh': 'TP. Hồ Chí Minh',
      'bà rịa - vũng tàu': 'Đồng Nai',
      'bà rịa vũng tàu': 'Đồng Nai',
      'ba ria vung tau': 'Đồng Nai',
    };

    // Check special mappings first
    for (final entry in cccdToProvince.entries) {
      if (lowerAddr.contains(entry.key)) {
        return entry.value;
      }
    }

    // Try matching against _vietnamProvinces directly
    for (final province in _vietnamProvinces) {
      if (lowerAddr.contains(province.toLowerCase())) {
        return province;
      }
    }

    // Try matching without Vietnamese accents
    final normalizedAddr = _removeAccents(lowerAddr);
    const provinceNoAccent = <String, String>{
      'ha noi': 'Hà Nội',
      'hai phong': 'Hải Phòng',
      'da nang': 'Đà Nẵng',
      'hue': 'Huế',
      'can tho': 'Cần Thơ',
      'quang ninh': 'Quảng Ninh',
      'thai nguyen': 'Thái Nguyên',
      'bac ninh': 'Bắc Ninh',
      'lao cai': 'Lào Cai',
      'yen bai': 'Yên Bái',
      'dien bien': 'Điện Biên',
      'son la': 'Sơn La',
      'nam dinh': 'Nam Định',
      'thanh hoa': 'Thanh Hóa',
      'nghe an': 'Nghệ An',
      'quang binh': 'Quảng Bình',
      'quang ngai': 'Quảng Ngãi',
      'phu yen': 'Phú Yên',
      'gia lai': 'Gia Lai',
      'dak lak': 'Đắk Lắk',
      'lam dong': 'Lâm Đồng',
      'dong nai': 'Đồng Nai',
      'tay ninh': 'Tây Ninh',
      'long an': 'Long An',
      'dong thap': 'Đồng Tháp',
      'vinh long': 'Vĩnh Long',
      'soc trang': 'Sóc Trăng',
      'ca mau': 'Cà Mau',
      'kien giang': 'Kiên Giang',
      'bac giang': 'Bắc Giang',
      'phu tho': 'Phú Thọ',
      'ha tinh': 'Hà Tĩnh',
      'binh dinh': 'Bình Định',
      'ninh binh': 'Nam Định',
      'thai binh': 'Nam Định',
      'ha nam': 'Nam Định',
      'hai duong': 'Hải Phòng',
      'hung yen': 'Hải Phòng',
      'quang nam': 'Đà Nẵng',
      'binh duong': 'TP. Hồ Chí Minh',
      'hoa binh': 'Hà Nội',
      'vinh phuc': 'Hà Nội',
      'lang son': 'Quảng Ninh',
      'bac kan': 'Thái Nguyên',
      'cao bang': 'Thái Nguyên',
      'ha giang': 'Lào Cai',
      'tuyen quang': 'Lào Cai',
      'lai chau': 'Điện Biên',
      'quang tri': 'Quảng Bình',
      'khanh hoa': 'Phú Yên',
      'kon tum': 'Gia Lai',
      'dak nong': 'Đắk Lắk',
      'ninh thuan': 'Lâm Đồng',
      'binh thuan': 'Lâm Đồng',
      'binh phuoc': 'Tây Ninh',
      'tien giang': 'Long An',
      'an giang': 'Đồng Tháp',
      'tra vinh': 'Vĩnh Long',
      'ben tre': 'Vĩnh Long',
      'bac lieu': 'Sóc Trăng',
      'hau giang': 'Cần Thơ',
    };
    for (final entry in provinceNoAccent.entries) {
      if (normalizedAddr.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Remove Vietnamese accents (static version for province matching)
  static String _removeAccents(String str) {
    const vietnamese =
        'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const nonVietnamese =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    String result = str;
    for (int i = 0; i < vietnamese.length; i++) {
      result = result.replaceAll(vietnamese[i], nonVietnamese[i]);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _isEmployee = authProvider.userRole == 'Employee';
    _loadEmployees();
  }

  Future<void> _loadDepartments() async {
    final deptResponse =
        await _apiService.getDepartments(pageSize: 100, isActive: true);
    if (deptResponse['isSuccess'] != false) {
      final deptData = deptResponse['data'] is List
          ? deptResponse['data']
          : (deptResponse['data']?['items'] ?? deptResponse['items'] ?? []);
      _departmentList =
          (deptData as List).map((d) => Department.fromJson(d)).toList();
      _departments = ['Tất cả', ..._departmentList.map((d) => d.name)];
      _departmentPositions = {};
      for (final dept in _departmentList) {
        if (dept.positions != null && dept.positions!.isNotEmpty) {
          _departmentPositions[dept.name] =
              dept.positions!.map((p) => p.toString()).toList();
        }
      }
      final allPositions = <String>{};
      for (final posList in _departmentPositions.values) {
        allPositions.addAll(posList);
      }
      _positions = allPositions.toList();
    }
  }

  Future<void> _loadEmployees({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      if (_isEmployee) {
        // Employee role: load only own profile via /api/employees/me
        final resp = await _apiService.getMyEmployee();
        if (mounted && resp['isSuccess'] == true && resp['data'] != null) {
          setState(() {
            _employees = [Employee.fromJson(resp['data'])];
            _filteredEmployees = List.from(_employees);
          });
        }
      } else {
        await _loadDepartments();
        final data = await _apiService.getEmployees(pageSize: 200);
        if (mounted) {
          setState(() {
            _employees = data.map((e) => Employee.fromJson(e)).toList();
            _applyFilters();
          });
        }
      }
    } catch (e) {
      _showError('Không thể tải danh sách nhân viên');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    _filteredEmployees = _employees.where((emp) {
      final matchesSearch = _searchQuery.isEmpty ||
          emp.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.employeeCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (emp.email?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          (emp.phone?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false);

      final matchesDepartment =
          _filterDepartment == 'Tất cả' || emp.department == _filterDepartment;

      final matchesStatus =
          _filterStatus == 'Tất cả' || emp.workStatusDisplay == _filterStatus;

      return matchesSearch && matchesDepartment && matchesStatus;
    }).toList();
    _currentPage = 1;
  }

  void _showError(String message) {
    if (!mounted) return;
    appNotification.showError(title: _l10n.error, message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    appNotification.showSuccess(title: 'Success', message: message);
  }

  // ─── Export Excel ─────────────────────────────────────────────────────────
  Future<void> _exportEmployeesExcel() async {
    setState(() => _isExporting = true);
    try {
      final result = await _apiService.exportEmployeesExcel();
      if (result['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(result['data']));
        await file_saver.saveFileBytes(bytes, 'nhan_vien_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        _showSuccess(_l10n.exportExcelSuccess);
      } else {
        _showError(result['message'] ?? _l10n.exportExcelFailed);
      }
    } catch (e) {
      _showError('Lỗi xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─── Import Excel ─────────────────────────────────────────────────────────
  Future<void> _importEmployeesExcel() async {
    // Show format instructions dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.upload_file, color: Color(0xFF1E3A5F)),
            SizedBox(width: 8),
            Text('Import nhân viên từ Excel', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600
              ? MediaQuery.of(context).size.width - 32
              : 460,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File Excel cần có các cột theo thứ tự sau:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text(
                'A: Mã NV*  |  B: Họ*  |  C: Tên*  |  D: Email công ty*\n'
                'E: Giới tính  |  F: Ngày sinh (dd/MM/yyyy)  |  G: CCCD\n'
                'H: Quê quán  |  I: Trình độ HV  |  J: Tình trạng HN\n'
                'K: SĐT  |  L: Email cá nhân  |  M: Địa chỉ thường trú\n'
                'N: Phòng ban  |  O: Chức vụ  |  P: Cấp bậc\n'
                'Q: Ngày vào làm (dd/MM/yyyy)  |  R: Ngân hàng\n'
                'S: Số TK  |  T: Tên TK ngân hàng',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              SizedBox(height: 12),
              Text(
                  '• Hàng đầu tiên là tiêu đề (bỏ qua khi import)\n• Các cột đánh dấu * là bắt buộc',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          AppDialogActions(
            onConfirm: () => Navigator.pop(ctx, true),
            confirmLabel: 'Chọn file Excel',
            confirmIcon: Icons.upload_file,
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (fileResult == null || fileResult.files.isEmpty) return;

    final bytes = fileResult.files.first.bytes;
    if (bytes == null) {
      _showError('Không thể đọc file');
      return;
    }

    setState(() => _isImporting = true);

    try {
      final excelFile = excel_lib.Excel.decodeBytes(bytes);
      final records = <Map<String, dynamic>>[];

      for (final tableName in excelFile.tables.keys) {
        final sheet = excelFile.tables[tableName];
        if (sheet == null || sheet.rows.length < 2) continue;

        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          String cellStr(int col) =>
              (col < row.length ? row[col]?.value?.toString().trim() : null) ??
              '';
          DateTime? parseDate(String s) {
            if (s.isEmpty) return null;
            try {
              final parts = s.split(RegExp(r'[/\-.]'));
              if (parts.length == 3) {
                final d = int.parse(parts[0]),
                    m = int.parse(parts[1]),
                    y = int.parse(parts[2]);
                return DateTime(y, m, d);
              }
            } catch (_) {}
            return null;
          }

          final employeeCode = cellStr(0);
          final lastName = cellStr(1);
          final firstName = cellStr(2);
          final companyEmail = cellStr(3);
          if (employeeCode.isEmpty || firstName.isEmpty || lastName.isEmpty) {
            continue;
          }

          records.add({
            'employeeCode': employeeCode,
            'lastName': lastName,
            'firstName': firstName,
            'companyEmail': companyEmail.isNotEmpty
                ? companyEmail
                : '$employeeCode@company.com',
            'gender': cellStr(4).isNotEmpty ? cellStr(4) : null,
            'dateOfBirth': parseDate(cellStr(5))?.toIso8601String(),
            'nationalIdNumber': cellStr(6).isNotEmpty ? cellStr(6) : null,
            'hometown': cellStr(7).isNotEmpty ? cellStr(7) : null,
            'educationLevel': cellStr(8).isNotEmpty ? cellStr(8) : null,
            'maritalStatus': cellStr(9).isNotEmpty ? cellStr(9) : null,
            'phoneNumber': cellStr(10).isNotEmpty ? cellStr(10) : null,
            'personalEmail': cellStr(11).isNotEmpty ? cellStr(11) : null,
            'permanentAddress': cellStr(12).isNotEmpty ? cellStr(12) : null,
            'department': cellStr(13).isNotEmpty ? cellStr(13) : null,
            'position': cellStr(14).isNotEmpty ? cellStr(14) : null,
            'level': cellStr(15).isNotEmpty ? cellStr(15) : null,
            'joinDate': parseDate(cellStr(16))?.toIso8601String(),
            'bankName': cellStr(17).isNotEmpty ? cellStr(17) : null,
            'bankAccountNumber': cellStr(18).isNotEmpty ? cellStr(18) : null,
            'bankAccountName': cellStr(19).isNotEmpty ? cellStr(19) : null,
            'employmentType': 0,
            'workStatus': 0,
          });
        }
        break; // only first sheet
      }

      if (records.isEmpty) {
        _showError('Không tìm thấy dữ liệu hợp lệ trong file');
        return;
      }

      final result = await _apiService.importEmployeesFromExcel(records);
      if (result['success'] == true) {
        final imported = result['imported'] ?? 0;
        final failed = result['failed'] ?? 0;
        final errors = result['errors'] as List? ?? [];

        if (!mounted) return;

        if (errors.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Import: $imported thành công, $failed lỗi'),
              content: SizedBox(
                width: MediaQuery.of(context).size.width < 600
                    ? MediaQuery.of(context).size.width - 32
                    : 400,
                height: 300,
                child: ListView(
                  children: errors
                      .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $e',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.red)),
                          ))
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Đóng'))
              ],
            ),
          );
        } else {
          _showSuccess('Import thành công $imported nhân viên!');
        }
        await _loadEmployees(showLoading: false);
      } else {
        _showError(result['message'] ?? 'Import thất bại');
      }
    } catch (e) {
      _showError('Lỗi đọc file: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isMobile = Responsive.isMobile(context);
    final activeCount =
        _employees.where((e) => e.workStatusDisplay == 'Đang làm việc').length;
    final probationCount =
        _employees.where((e) => e.workStatusDisplay == 'Đang thử việc').length;
    final deptCount = _employees
        .map((e) => e.department)
        .where((d) => d != null)
        .toSet()
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Gradient header
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18,
                isMobile ? 14 : 24, isMobile ? 12 : 18),
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
            child: isMobile
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.people_alt,
                            size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_l10n.hrManagement,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            Text('${_filteredEmployees.length} nhân viên',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Colors.white.withValues(alpha: 0.8))),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.person_add,
                              size: 18, color: Colors.white),
                        ),
                        onPressed: () => _showEmployeeForm(null),
                        tooltip: _l10n.addEmployee,
                      ),
                      GestureDetector(
                        onTap: () => setState(
                            () => _showMobileFilters = !_showMobileFilters),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                                alpha: _showMobileFilters ? 0.25 : 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              Icon(
                                  _showMobileFilters
                                      ? Icons.filter_alt
                                      : Icons.filter_alt_outlined,
                                  size: 18,
                                  color: Colors.white),
                              if (_searchQuery.isNotEmpty ||
                                  _filterDepartment != 'Tất cả' ||
                                  _filterStatus != 'Tất cả')
                                Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                            color: Colors.orangeAccent,
                                            shape: BoxShape.circle))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
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
                          if (v == 'import') _importEmployeesExcel();
                          if (v == 'export') _exportEmployeesExcel();
                          if (v == 'dept') NavigationNotifier.goToDepartments();
                        },
                        itemBuilder: (_) => [
                          if (_perm.canCreate(_module))
                          PopupMenuItem(
                              value: 'import',
                              child: Row(children: [
                                const Icon(Icons.upload_file, size: 18),
                                const SizedBox(width: 10),
                                Text(_l10n.importExcel)
                              ])),
                          if (_perm.canExport(_module))
                          PopupMenuItem(
                              value: 'export',
                              child: Row(children: [
                                const Icon(Icons.download, size: 18),
                                const SizedBox(width: 10),
                                Text(_l10n.exportExcel)
                              ])),
                          PopupMenuItem(
                              value: 'dept',
                              child: Row(children: [
                                const Icon(Icons.business, size: 18),
                                const SizedBox(width: 10),
                                Text(_l10n.department)
                              ])),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.people_alt,
                            size: 22, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _l10n.hrManagement,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          Text(
                            '${_filteredEmployees.length} nhân viên',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_perm.canCreate(_module))
                      _buildHeaderActionBtn(Icons.person_add, _l10n.addEmployee,
                          () => _showEmployeeForm(null)),
                      if (_perm.canCreate(_module))
                      const SizedBox(width: 8),
                      if (_perm.canCreate(_module))
                      _buildHeaderActionBtn(
                        Icons.upload_file,
                        _isImporting ? 'Importing...' : _l10n.importExcel,
                        _isImporting ? null : _importEmployeesExcel,
                      ),
                      if (_perm.canExport(_module))
                      const SizedBox(width: 8),
                      if (_perm.canExport(_module))
                      _buildHeaderActionBtn(
                        Icons.download,
                        _isExporting ? 'Exporting...' : _l10n.exportExcel,
                        _isExporting ? null : _exportEmployeesExcel,
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderActionBtn(Icons.business, _l10n.department,
                          () => NavigationNotifier.goToDepartments()),
                    ],
                  ),
          ),

          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 10 : 16,
                  isMobile ? 10 : 16, isMobile ? 10 : 16, 8),
              child: Column(
                children: [
                  // Stats cards
                  if (isMobile) ...[
                    InkWell(
                      onTap: () => setState(
                          () => _showMobileSummary = !_showMobileSummary),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined,
                                size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Tổng quan',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Colors.blue.shade700)),
                            const Spacer(),
                            Icon(
                                _showMobileSummary
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: Colors.blue.shade700),
                          ],
                        ),
                      ),
                    ),
                    if (_showMobileSummary) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: _buildStatCard(
                                  'Tổng NV',
                                  '${_employees.length}',
                                  Icons.people_outline,
                                  const Color(0xFF1E3A5F))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildStatCard(
                                  'Đang làm',
                                  '$activeCount',
                                  Icons.check_circle_outline,
                                  const Color(0xFF1E3A5F))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildStatCard(
                                  'Thử việc',
                                  '$probationCount',
                                  Icons.hourglass_bottom,
                                  const Color(0xFFF59E0B))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildStatCard(
                                  _l10n.department,
                                  '$deptCount',
                                  Icons.business_outlined,
                                  const Color(0xFF0F2340))),
                        ],
                      ),
                    ],
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                            child: _buildStatCard(
                                'Tổng NV',
                                '${_employees.length}',
                                Icons.people_outline,
                                const Color(0xFF1E3A5F))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _buildStatCard(
                                'Đang làm',
                                '$activeCount',
                                Icons.check_circle_outline,
                                const Color(0xFF1E3A5F))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _buildStatCard(
                                'Thử việc',
                                '$probationCount',
                                Icons.hourglass_bottom,
                                const Color(0xFFF59E0B))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _buildStatCard(
                                _l10n.department,
                                '$deptCount',
                                Icons.business_outlined,
                                const Color(0xFF0F2340))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Filters
                  if (!isMobile || _showMobileFilters) ...[
                    _buildFilters(),
                    const SizedBox(height: 12),
                  ],

                  // Content
                  Expanded(
                    child: _isLoading
                        ? const LoadingWidget(message: 'Đang tải nhân viên...')
                        : _filteredEmployees.isEmpty
                            ? EmptyState(
                                icon: Icons.people,
                                title: 'Không có nhân viên',
                                description: _searchQuery.isNotEmpty
                                    ? 'No matching employees found'
                                    : _l10n.addFirstEmployee,
                                actionLabel: _l10n.addEmployee,
                                onAction: () => _showEmployeeForm(null),
                              )
                            : _buildEmployeesList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickAddDepartmentDialog(
      StateSetter setDialogState, TextEditingController departmentController) {
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final sortOrderController = TextEditingController(text: '0');

    String? selectedParentId;
    String? selectedManagerId;

    final List<String> defaultPositionSuggestions = [
      'Giám đốc', 'Phó Giám đốc', 'Trưởng phòng', 'Phó phòng',
      'Trưởng nhóm', 'Phó nhóm', 'Nhân viên', 'Thực tập sinh',
      'Chuyên viên', 'Kế toán trưởng', 'Thư ký', 'Tổ trưởng',
    ];
    List<String> selectedPositions = [];

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDeptDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Mã phòng ban *',
                      hintText: 'VD: IT, HR, SALES...',
                      prefixIcon: Icon(Icons.code),
                    ),
                    validator: (v) =>
                        v?.isEmpty == true ? 'Vui lòng nhập mã' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên phòng ban *',
                      hintText: 'VD: Phòng Công nghệ Thông tin',
                      prefixIcon: Icon(Icons.business),
                    ),
                    autofocus: true,
                    validator: (v) =>
                        v?.isEmpty == true ? 'Vui lòng nhập tên' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedParentId,
                    decoration: const InputDecoration(
                      labelText: 'Phòng ban cha',
                      prefixIcon: Icon(Icons.account_tree),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Không có (Phòng ban gốc)'),
                      ),
                      ..._departmentList
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(d.name),
                              )),
                    ],
                    onChanged: (v) =>
                        setDeptDialogState(() => selectedParentId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedManagerId,
                    decoration: const InputDecoration(
                      labelText: 'Quản lý phòng ban',
                      prefixIcon: Icon(Icons.person),
                      hintText: 'Chọn người quản lý...',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Chưa phân công',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      ..._employees.map((emp) {
                        final fullName =
                            '${emp.lastName} ${emp.firstName}'
                                .trim();
                        return DropdownMenuItem(
                          value: emp.id,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(fullName,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if ((emp.position ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(emp.position!,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500])),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) =>
                        setDeptDialogState(() => selectedManagerId = v),
                  ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Chức vụ trong phòng ban',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedPositions.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: selectedPositions
                                .map((pos) => Chip(
                                      label: Text(pos,
                                          style:
                                              const TextStyle(fontSize: 13)),
                                      deleteIcon:
                                          const Icon(Icons.close, size: 16),
                                      onDeleted: () {
                                        setDeptDialogState(() =>
                                            selectedPositions.remove(pos));
                                      },
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ))
                                .toList(),
                          ),
                        const SizedBox(height: 6),
                        Autocomplete<String>(
                          optionsBuilder:
                              (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return defaultPositionSuggestions.where(
                                  (s) => !selectedPositions.contains(s));
                            }
                            return defaultPositionSuggestions
                                .where(
                                    (s) => !selectedPositions.contains(s))
                                .where((s) => s.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase()));
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                hintText:
                                    'Nhập chức vụ hoặc chọn gợi ý...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 8),
                              ),
                              onSubmitted: (value) {
                                final trimmed = value.trim();
                                if (trimmed.isNotEmpty &&
                                    !selectedPositions.contains(trimmed)) {
                                  setDeptDialogState(
                                      () => selectedPositions.add(trimmed));
                                }
                                controller.clear();
                              },
                            );
                          },
                          onSelected: (String selection) {
                            if (!selectedPositions.contains(selection)) {
                              setDeptDialogState(
                                  () => selectedPositions.add(selection));
                            }
                          },
                        ),
                        if (selectedPositions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: defaultPositionSuggestions
                                  .take(6)
                                  .map((s) => ActionChip(
                                        label: Text(s,
                                            style: const TextStyle(
                                                fontSize: 12)),
                                        onPressed: () {
                                          if (!selectedPositions
                                              .contains(s)) {
                                            setDeptDialogState(() =>
                                                selectedPositions.add(s));
                                          }
                                        },
                                        visualDensity:
                                            VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap,
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: sortOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Thứ tự hiển thị',
                      prefixIcon: Icon(Icons.sort),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          );
          Future<Null> onSave() async {
            if (!formKey.currentState!.validate()) return;
            final name = nameController.text.trim();
            final code = codeController.text.trim();
            final result = await _apiService.createDepartment(
              code: code,
              name: name,
              description: descController.text.trim().isEmpty
                  ? null
                  : descController.text.trim(),
              parentDepartmentId: selectedParentId,
              managerId: selectedManagerId,
              sortOrder: int.tryParse(sortOrderController.text) ?? 0,
              positions: selectedPositions.isNotEmpty ? selectedPositions : null,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (result['isSuccess'] == true) {
              await _loadDepartments();
              setDialogState(() {
                departmentController.text = name;
              });
              if (mounted) {
                NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã thêm phòng ban "$name"');
              }
            } else {
              if (mounted) {
                NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi tạo phòng ban');
              }
            }
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Thêm phòng ban mới'),
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(_l10n.cancel)),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tạo mới'),
                              onPressed: onSave),
                        ]),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.business, color: Color(0xFF1E3A5F)),
                SizedBox(width: 8),
                Text('Thêm phòng ban mới', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: formContent,
            ),
            actions: [
              AppDialogActions(
                onConfirm: onSave,
                confirmLabel: 'Tạo mới',
                confirmIcon: Icons.add,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderActionBtn(
      IconData icon, String label, VoidCallback? onTap) {
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
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
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
      child: MediaQuery.of(context).size.width < 600
          ? Column(
              children: [
                // Search field
                Container(
                  height: 36,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên, mã NV, SĐT...',
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon:
                          Icon(Icons.search, size: 18, color: Colors.grey[500]),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
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
                            BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _applyFilters();
                      });
                    },
                  ),
                ),
                Row(
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
                          child: DropdownButton<String>(
                            value: _filterDepartment,
                            isExpanded: true,
                            isDense: true,
                            icon:
                                const Icon(Icons.keyboard_arrow_down, size: 18),
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color),
                            items: _departments.map((dept) {
                              return DropdownMenuItem(
                                value: dept,
                                child: Row(
                                  children: [
                                    Icon(Icons.business,
                                        size: 14, color: Colors.grey[500]),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(dept,
                                            overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              );
                            }).toList(),
                            selectedItemBuilder: (context) =>
                                _departments.map((dept) {
                              return Row(
                                children: [
                                  Icon(Icons.business,
                                      size: 14,
                                      color: Theme.of(context).primaryColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(dept,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 13))),
                                ],
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _filterDepartment = value;
                                  _applyFilters();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                          child: DropdownButton<String>(
                            value: _filterStatus,
                            isExpanded: true,
                            isDense: true,
                            icon:
                                const Icon(Icons.keyboard_arrow_down, size: 18),
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color),
                            items: _statuses.map((status) {
                              return DropdownMenuItem(
                                value: status,
                                child: Row(
                                  children: [
                                    Icon(Icons.circle,
                                        size: 10,
                                        color: _getStatusColor(status)),
                                    const SizedBox(width: 6),
                                    Text(status),
                                  ],
                                ),
                              );
                            }).toList(),
                            selectedItemBuilder: (context) =>
                                _statuses.map((status) {
                              return Row(
                                children: [
                                  Icon(Icons.filter_list,
                                      size: 14,
                                      color: Theme.of(context).primaryColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(status,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 13))),
                                ],
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _filterStatus = value;
                                  _applyFilters();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people,
                          color: Theme.of(context).primaryColor, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_filteredEmployees.length} nhân viên',
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
            )
          : Row(
              children: [
                // Search field
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm theo tên, mã NV, SĐT...',
                        hintStyle:
                            TextStyle(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.search,
                            size: 18, color: Colors.grey[500]),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Theme.of(context).primaryColor),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      child: DropdownButton<String>(
                        value: _filterDepartment,
                        isExpanded: true,
                        isDense: true,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        items: _departments.map((dept) {
                          return DropdownMenuItem(
                            value: dept,
                            child: Row(
                              children: [
                                Icon(Icons.business,
                                    size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(dept,
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          );
                        }).toList(),
                        selectedItemBuilder: (context) =>
                            _departments.map((dept) {
                          return Row(
                            children: [
                              Icon(Icons.business,
                                  size: 14,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(dept,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13))),
                            ],
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _filterDepartment = value;
                              _applyFilters();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      child: DropdownButton<String>(
                        value: _filterStatus,
                        isExpanded: true,
                        isDense: true,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        items: _statuses.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Row(
                              children: [
                                Icon(Icons.circle,
                                    size: 10, color: _getStatusColor(status)),
                                const SizedBox(width: 6),
                                Text(status),
                              ],
                            ),
                          );
                        }).toList(),
                        selectedItemBuilder: (context) =>
                            _statuses.map((status) {
                          return Row(
                            children: [
                              Icon(Icons.filter_list,
                                  size: 14,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(status,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13))),
                            ],
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _filterStatus = value;
                              _applyFilters();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people,
                          color: Theme.of(context).primaryColor, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_filteredEmployees.length} nhân viên',
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
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Đang làm việc':
        return const Color(0xFF1E3A5F);
      case 'Đang thử việc':
        return const Color(0xFF1E3A5F);
      case 'Nghỉ phép':
        return const Color(0xFFF59E0B);
      case 'Đã nghỉ việc':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFA1A1AA);
    }
  }

  Widget _buildEmployeesList() {
    final isMobile = Responsive.isMobile(context);
    final totalCount = _filteredEmployees.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = (_currentPage * _pageSize).clamp(0, totalCount);
    final displayList = isMobile
        ? _filteredEmployees
        : _filteredEmployees.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadEmployees,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
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
                    child: _buildEmployeeCard(displayList[index]),
                  ),
                );
              },
            ),
          ),
        ),
        if (!isMobile) Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                totalCount > 0
                    ? 'Hiển thị ${startIndex + 1}-$endIndex / $totalCount'
                    : 'Không có dữ liệu',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Hiển thị:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                        items: _pageSizeOptions
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text('$s')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _pageSize = v;
                              _currentPage = 1;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page, size: 20),
                    onPressed: _currentPage > 1
                        ? () => setState(() => _currentPage = 1)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: _currentPage > 1
                        ? () => setState(() => _currentPage--)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$_currentPage / $totalPages',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: _currentPage < totalPages
                        ? () => setState(() => _currentPage++)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page, size: 20),
                    onPressed: _currentPage < totalPages
                        ? () => setState(() => _currentPage = totalPages)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    return InkWell(
      onTap: () => _showEmployeeDetails(employee),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  Theme.of(context).primaryColor.withValues(alpha: 0.15),
              backgroundImage: employee.avatarUrl != null
                  ? NetworkImage(_apiService.getFileUrl(employee.avatarUrl!))
                  : null,
              onBackgroundImageError: employee.avatarUrl != null ? (_, __) {} : null,
              child: employee.avatarUrl == null
                  ? Icon(
                      employee.gender?.toLowerCase() == 'female' ||
                              employee.gender?.toLowerCase() == 'nữ'
                          ? Icons.woman_rounded
                          : Icons.man_rounded,
                      color: Theme.of(context).primaryColor,
                      size: 18,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(employee.employeeCode,
                          style: const TextStyle(
                              color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.w500)),
                      if (employee.department != null) ...[
                        const Text(' · ',
                            style: TextStyle(
                                color: Color(0xFFA1A1AA), fontSize: 11)),
                        Flexible(
                            child: Text(employee.department!,
                                style: const TextStyle(
                                    color: Color(0xFF71717A), fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (employee.position != null) ...[
                        const Icon(Icons.work_outline, size: 11, color: Color(0xFFA1A1AA)),
                        const SizedBox(width: 3),
                        Flexible(
                            child: Text(employee.position!,
                                style: const TextStyle(
                                    color: Color(0xFF71717A), fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                      ],
                      if (employee.position != null && employee.phone != null && employee.phone!.isNotEmpty)
                        const Text(' · ',
                            style: TextStyle(
                                color: Color(0xFFA1A1AA), fontSize: 11)),
                      if (employee.phone != null && employee.phone!.isNotEmpty) ...[
                        const Icon(Icons.phone_outlined, size: 11, color: Color(0xFFA1A1AA)),
                        const SizedBox(width: 3),
                        Text(employee.phone!,
                            style: const TextStyle(
                                color: Color(0xFF71717A), fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    _showEmployeeDetails(employee);
                    break;
                  case 'edit':
                    _showEmployeeForm(employee);
                    break;
                  case 'call':
                    _callEmployee(employee);
                    break;
                  case 'salary':
                    NavigationNotifier.goToSalarySettings();
                    break;
                  case 'delete':
                    _confirmDeleteEmployee(employee);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 20),
                      SizedBox(width: 12),
                      Text('View Details'),
                    ],
                  ),
                ),
                if (_perm.canEdit(_module))
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text('Edit'),
                    ],
                  ),
                ),
                if (employee.phone != null && employee.phone!.isNotEmpty)
                  const PopupMenuItem(
                    value: 'call',
                    child: Row(
                      children: [
                        Icon(Icons.phone, size: 20, color: Colors.green),
                        SizedBox(width: 12),
                        Text('Call', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'salary',
                  child: Row(
                    children: [
                      Icon(Icons.payments, size: 20, color: Colors.blue),
                      SizedBox(width: 12),
                      Text('Salary Settings',
                          style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
                if (_perm.canDelete(_module))
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(_l10n.delete,
                          style: const TextStyle(color: Colors.red)),
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

  void _callEmployee(Employee employee) {
    if (employee.phone != null && employee.phone!.isNotEmpty) {
      launchUrl(Uri.parse('tel:${employee.phone}'));
    }
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showEmployeeForm(Employee? employee) {
    final isEditing = employee != null;

    final employeeCodeController =
        TextEditingController(text: employee?.employeeCode ?? '');
    final fullNameController =
        TextEditingController(text: employee?.fullName ?? '');
    final phoneController = TextEditingController(text: employee?.phone ?? '');
    final emailController = TextEditingController(text: employee?.email ?? '');
    final companyEmailController =
        TextEditingController(text: employee?.companyEmail ?? '');
    final permanentAddressController =
        TextEditingController(text: employee?.permanentAddress ?? '');
    final temporaryAddressController =
        TextEditingController(text: employee?.temporaryAddress ?? '');
    final emergencyContactController =
        TextEditingController(text: employee?.emergencyContact ?? '');
    final emergencyContactNameController =
        TextEditingController(text: employee?.emergencyContactName ?? '');
    final departmentController =
        TextEditingController(text: employee?.department ?? '');
    final positionController =
        TextEditingController(text: employee?.position ?? '');
    final bankAccountNameController = TextEditingController(
        text: employee?.bankAccountName ??
            (isEditing && employee.fullName.isNotEmpty
                ? _removeVietnameseAccents(employee.fullName).toUpperCase()
                : ''));
    final bankAccountNumberController =
        TextEditingController(text: employee?.bankAccountNumber ?? '');
    final nationalIdController =
        TextEditingController(text: employee?.nationalId ?? '');
    String? selectedHometown = employee?.hometown;

    String? selectedBank = employee?.bankName;
    String? selectedGender = employee?.genderDisplay;
    String? selectedMaritalStatus = employee?.maritalStatusDisplay;
    String? selectedEducationLevel = employee?.educationLevel;
    String selectedWorkStatus = employee?.workStatusDisplay ?? 'Đang làm việc';
    // ignore: unused_local_variable
    DateTime? selectedDateOfBirth = employee?.dateOfBirth;
    DateTime? selectedJoinDate = employee?.joinDate;
    String? selectedManagerId = employee?.managerId;
    String? selectedManagerName = employee?.managerName;

    // Photo URLs
    String? photoUrl = employee?.avatarUrl;
    String? cccdFrontUrl = employee?.idCardFrontUrl;
    String? cccdBackUrl = employee?.idCardBackUrl;

    // Auto-fill bank account name from fullName
    // ignore: unused_local_variable (selectedHometown tracked separately)
    void autoFillBankAccountName() {
      if (bankAccountNameController.text.isEmpty &&
          fullNameController.text.isNotEmpty) {
        bankAccountNameController.text =
            _removeVietnameseAccents(fullNameController.text).toUpperCase();
      }
    }

    final isMobileForm = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobileForm ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== ẢNH ĐẠI DIỆN =====
                  _buildSectionHeader('Ảnh đại diện'),
                  Center(
                    child: InkWell(
                      onTap: () async {
                        final path = await _pickAndCropImage(
                          uploadFn: _apiService.uploadEmployeePhoto,
                          isCircle: true,
                        );
                        if (path != null) {
                          setDialogState(() => photoUrl = path);
                        }
                      },
                      borderRadius: BorderRadius.circular(60),
                      child: CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: photoUrl != null
                            ? NetworkImage(_apiService.getFileUrl(photoUrl!))
                            : null,
                        onBackgroundImageError: photoUrl != null ? (_, __) {} : null,
                        child: photoUrl == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selectedGender == 'Nữ'
                                        ? Icons.woman_rounded
                                        : Icons.man_rounded,
                                    size: 40,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Tải ảnh lên',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500])),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ===== THÔNG TIN CƠ BẢN =====
                  _buildSectionHeader('Thông tin cơ bản'),

                  // QR CCCD Scanner button
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await showDialog<String>(
                          context: context,
                          builder: (_) => const _CccdQrScannerDialog(),
                        );
                        if (result != null && result.isNotEmpty) {
                          final parsed = _parseCccdQr(result);
                          if (parsed != null) {
                            setDialogState(() {
                              if (parsed['cccd'] != null) {
                                nationalIdController.text = parsed['cccd']!;
                              }
                              if (parsed['fullName'] != null) {
                                fullNameController.text = parsed['fullName']!;
                                autoFillBankAccountName();
                              }
                              if (parsed['dob'] != null) {
                                selectedDateOfBirth =
                                    parsed['dob'] as DateTime?;
                              }
                              if (parsed['gender'] != null) {
                                selectedGender = parsed['gender'];
                              }
                              if (parsed['address'] != null) {
                                permanentAddressController.text =
                                    parsed['address']!;
                              }
                              if (parsed['province'] != null) {
                                selectedHometown = parsed['province'];
                              }
                            });
                            NotificationOverlayManager().showSuccess(title: 'CCCD', message: 'Đã điền thông tin từ CCCD');
                          } else {
                            NotificationOverlayManager().showError(title: 'Lỗi', message: 'Mã QR không đúng định dạng CCCD');
                          }
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('Quét QR căn cước công dân'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0C56D0),
                        side: const BorderSide(color: Color(0xFF0C56D0)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),

                  if (isMobileForm) ...[
                    TextField(
                      controller: employeeCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã nhân viên *',
                        prefixIcon: Icon(Icons.badge),
                      ),
                      enabled: !isEditing,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên nhân viên *',
                        prefixIcon: Icon(Icons.person),
                        hintText: 'VD: Nguyễn Văn A',
                      ),
                      onChanged: (_) => autoFillBankAccountName(),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: employeeCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Mã nhân viên *',
                              prefixIcon: Icon(Icons.badge),
                            ),
                            enabled: !isEditing,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: fullNameController,
                            decoration: const InputDecoration(
                              labelText: 'Tên nhân viên *',
                              prefixIcon: Icon(Icons.person),
                              hintText: 'VD: Nguyễn Văn A',
                            ),
                            onChanged: (_) => autoFillBankAccountName(),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (isMobileForm) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _genders.contains(selectedGender)
                          ? selectedGender
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Giới tính',
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: _genders
                          .map((g) =>
                              DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedGender = value),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              selectedDateOfBirth ?? DateTime(1990),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setDialogState(() => selectedDateOfBirth = date);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: _l10n.birthDate,
                          prefixIcon: const Icon(Icons.cake),
                        ),
                        child: Text(
                          selectedDateOfBirth != null
                              ? DateFormat('dd/MM/yyyy')
                                  .format(selectedDateOfBirth!)
                              : 'Chọn ngày',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _maritalStatuses.contains(selectedMaritalStatus)
                              ? selectedMaritalStatus
                              : null,
                      decoration: const InputDecoration(
                        labelText: 'Tình trạng hôn nhân',
                        prefixIcon: Icon(Icons.favorite),
                      ),
                      items: _maritalStatuses
                          .map((s) =>
                              DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (value) => setDialogState(
                          () => selectedMaritalStatus = value),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _genders.contains(selectedGender)
                                ? selectedGender
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Giới tính',
                              prefixIcon: Icon(Icons.wc),
                            ),
                            items: _genders
                                .map((g) =>
                                    DropdownMenuItem(value: g, child: Text(g)))
                                .toList(),
                            onChanged: (value) =>
                                setDialogState(() => selectedGender = value),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate:
                                    selectedDateOfBirth ?? DateTime(1990),
                                firstDate: DateTime(1950),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() => selectedDateOfBirth = date);
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: _l10n.birthDate,
                                prefixIcon: const Icon(Icons.cake),
                              ),
                              child: Text(
                                selectedDateOfBirth != null
                                    ? DateFormat('dd/MM/yyyy')
                                        .format(selectedDateOfBirth!)
                                    : 'Chọn ngày',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                _maritalStatuses.contains(selectedMaritalStatus)
                                    ? selectedMaritalStatus
                                    : null,
                            decoration: const InputDecoration(
                              labelText: 'Tình trạng hôn nhân',
                              prefixIcon: Icon(Icons.favorite),
                            ),
                            items: _maritalStatuses
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (value) => setDialogState(
                                () => selectedMaritalStatus = value),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: nationalIdController,
                    decoration: const InputDecoration(
                      labelText: 'Số CCCD/CMND',
                      prefixIcon: Icon(Icons.credit_card),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Quê quán — Autocomplete 34 tỉnh thành
                  Autocomplete<String>(
                    initialValue:
                        TextEditingValue(text: selectedHometown ?? ''),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _vietnamProvinces;
                      }
                      return _vietnamProvinces.where((p) => p
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase()));
                    },
                    onSelected: (String selection) {
                      selectedHometown = selection;
                    },
                    fieldViewBuilder: (context, controller, focusNode,
                        onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (value) => selectedHometown = value,
                        decoration: const InputDecoration(
                          labelText: 'Quê quán',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          hintText: 'Chọn hoặc tìm tỉnh/thành...',
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight: 250,
                                maxWidth: MediaQuery.of(context)
                                            .size
                                            .width <
                                        600
                                    ? MediaQuery.of(context).size.width -
                                        48
                                    : 320),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.location_on,
                                      size: 16, color: Color(0xFF1E3A5F)),
                                  title: Text(option,
                                      style:
                                          const TextStyle(fontSize: 13)),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Trình độ học vấn
                  DropdownButtonFormField<String>(
                    initialValue: const [
                      'Trung học',
                      'Trung cấp',
                      'Cao đẳng',
                      'Đại học',
                      'Thạc sĩ',
                      'Tiến sĩ',
                      'Khác'
                    ].contains(selectedEducationLevel)
                        ? selectedEducationLevel
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Trình độ học vấn',
                      prefixIcon: Icon(Icons.school),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'Trung học', child: Text('Trung học')),
                      DropdownMenuItem(
                          value: 'Trung cấp', child: Text('Trung cấp')),
                      DropdownMenuItem(
                          value: 'Cao đẳng', child: Text('Cao đẳng')),
                      DropdownMenuItem(
                          value: 'Đại học', child: Text('Đại học')),
                      DropdownMenuItem(
                          value: 'Thạc sĩ', child: Text('Thạc sĩ')),
                      DropdownMenuItem(
                          value: 'Tiến sĩ', child: Text('Tiến sĩ')),
                      DropdownMenuItem(
                          value: 'Khác', child: Text('Khác')),
                    ],
                    onChanged: (value) {
                      selectedEducationLevel = value;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Thông tin liên hệ
                  _buildSectionHeader('Thông tin liên hệ'),
                  if (isMobileForm) ...[
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: _l10n.phone,
                        prefixIcon: const Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email cá nhân',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneController,
                            decoration: InputDecoration(
                              labelText: _l10n.phone,
                              prefixIcon: const Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email cá nhân',
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (isMobileForm) ...[
                    TextField(
                      controller: emergencyContactNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên người thân',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emergencyContactController,
                      decoration: const InputDecoration(
                        labelText: 'SĐT người thân',
                        prefixIcon: Icon(Icons.contact_phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: emergencyContactNameController,
                            decoration: const InputDecoration(
                              labelText: 'Tên người thân',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: emergencyContactController,
                            decoration: const InputDecoration(
                              labelText: 'SĐT người thân',
                              prefixIcon: Icon(Icons.contact_phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: permanentAddressController,
                    decoration: InputDecoration(
                      labelText: _l10n.address,
                      prefixIcon: const Icon(Icons.home),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: temporaryAddressController,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ tạm trú',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Thông tin công việc
                  _buildSectionHeader('Thông tin công việc'),
                  if (isMobileForm) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _departments
                                    .where((d) => d != 'Tất cả')
                                    .contains(departmentController.text)
                                ? departmentController.text
                                : null,
                            decoration: InputDecoration(
                              labelText: _l10n.department,
                              prefixIcon: const Icon(Icons.business),
                              hintText: 'Select department',
                            ),
                            items: _departments
                                .where((d) => d != 'Tất cả')
                                .map((d) =>
                                    DropdownMenuItem(value: d, child: Text(d)))
                                .toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                departmentController.text = value ?? '';
                                positionController.text = '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF1E3A5F)),
                          tooltip: 'Thêm phòng ban mới',
                          onPressed: () => _showQuickAddDepartmentDialog(
                              setDialogState, departmentController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final deptName = departmentController.text;
                        final availablePositions = deptName.isNotEmpty &&
                                _departmentPositions.containsKey(deptName)
                            ? _departmentPositions[deptName]!
                            : _positions;
                        return DropdownButtonFormField<String>(
                          initialValue: availablePositions
                                  .contains(positionController.text)
                              ? positionController.text
                              : null,
                          decoration: InputDecoration(
                            labelText: _l10n.position,
                            prefixIcon: const Icon(Icons.work),
                            hintText: deptName.isEmpty
                                ? 'Select department first'
                                : 'Select position',
                          ),
                          items: availablePositions
                              .map((p) => DropdownMenuItem(
                                  value: p, child: Text(p)))
                              .toList(),
                          onChanged: deptName.isEmpty
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    positionController.text = value ?? '';
                                  });
                                },
                        );
                      },
                    ),
                  ] else ...[
                    Row(
                      children: [
                        // Department dropdown from API
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _departments
                                    .where((d) => d != 'Tất cả')
                                    .contains(departmentController.text)
                                ? departmentController.text
                                : null,
                            decoration: InputDecoration(
                              labelText: _l10n.department,
                              prefixIcon: const Icon(Icons.business),
                              hintText: 'Select department',
                            ),
                            items: _departments
                                .where((d) => d != 'Tất cả')
                                .map((d) =>
                                    DropdownMenuItem(value: d, child: Text(d)))
                                .toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                departmentController.text = value ?? '';
                                // Reset position when department changes
                                positionController.text = '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Quick add department button
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF1E3A5F)),
                          tooltip: 'Thêm phòng ban mới',
                          onPressed: () => _showQuickAddDepartmentDialog(
                              setDialogState, departmentController),
                        ),
                        const SizedBox(width: 16),
                        // Position dropdown linked to department
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final deptName = departmentController.text;
                              final availablePositions = deptName.isNotEmpty &&
                                      _departmentPositions.containsKey(deptName)
                                  ? _departmentPositions[deptName]!
                                  : _positions;
                              return DropdownButtonFormField<String>(
                                initialValue: availablePositions
                                        .contains(positionController.text)
                                    ? positionController.text
                                    : null,
                                decoration: InputDecoration(
                                  labelText: _l10n.position,
                                  prefixIcon: const Icon(Icons.work),
                                  hintText: deptName.isEmpty
                                      ? 'Select department first'
                                      : 'Select position',
                                ),
                                items: availablePositions
                                    .map((p) => DropdownMenuItem(
                                        value: p, child: Text(p)))
                                    .toList(),
                                onChanged: deptName.isEmpty
                                    ? null
                                    : (value) {
                                        setDialogState(() {
                                          positionController.text = value ?? '';
                                        });
                                      },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Manager field - show for all positions
                  if (positionController.text.isNotEmpty) ...[
                    Autocomplete<Employee>(
                      initialValue:
                          TextEditingValue(text: selectedManagerName ?? ''),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final managers = _employees.where((e) =>
                            e.id != employee?.id &&
                            e.position != null &&
                            e.position != 'Nhân viên' &&
                            e.position != 'Thực tập sinh');
                        if (textEditingValue.text.isEmpty) {
                          return managers.take(10);
                        }
                        return managers.where((e) => e.fullName
                            .toLowerCase()
                            .contains(textEditingValue.text.toLowerCase()));
                      },
                      displayStringForOption: (Employee emp) =>
                          '${emp.fullName} (${emp.position ?? ""})',
                      onSelected: (Employee selection) {
                        setDialogState(() {
                          selectedManagerId = selection.id;
                          selectedManagerName = selection.fullName;
                        });
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        if (controller.text.isEmpty &&
                            selectedManagerName != null) {
                          controller.text = selectedManagerName!;
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Người quản lý',
                            prefixIcon: Icon(Icons.supervisor_account),
                            hintText: 'Chọn quản lý',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isMobileForm) ...[
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedJoinDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setDialogState(() => selectedJoinDate = date);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Ngày vào làm',
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          selectedJoinDate != null
                              ? DateFormat('dd/MM/yyyy')
                                  .format(selectedJoinDate!)
                              : 'Chọn ngày',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: companyEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Email công ty',
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'VD: nva@company.com',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedJoinDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setDialogState(() => selectedJoinDate = date);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Ngày vào làm',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                selectedJoinDate != null
                                    ? DateFormat('dd/MM/yyyy')
                                        .format(selectedJoinDate!)
                                    : 'Chọn ngày',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: companyEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Email công ty',
                              prefixIcon: Icon(Icons.alternate_email),
                              hintText: 'VD: nva@company.com',
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _statuses
                                  .where((s) => s != 'Tất cả')
                                  .contains(selectedWorkStatus)
                              ? selectedWorkStatus
                              : 'Đang làm việc',
                          decoration: InputDecoration(
                            labelText: _l10n.status,
                            prefixIcon: const Icon(Icons.toggle_on),
                          ),
                          items: _statuses
                              .where((s) => s != 'Tất cả')
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedWorkStatus = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Thông tin ngân hàng
                  _buildSectionHeader('Thông tin ngân hàng'),
                  Autocomplete<String>(
                          initialValue:
                              TextEditingValue(text: selectedBank ?? ''),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return _vietnamBanks;
                            }
                            return _vietnamBanks.where((bank) => bank
                                .toLowerCase()
                                .contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (String selection) {
                            setDialogState(() => selectedBank = selection);
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            if (controller.text.isEmpty &&
                                selectedBank != null &&
                                selectedBank!.isNotEmpty) {
                              controller.text = selectedBank!;
                            }
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              onChanged: (value) =>
                                  setDialogState(() => selectedBank = value),
                              decoration: const InputDecoration(
                                labelText: 'Ngân hàng',
                                prefixIcon: Icon(Icons.account_balance),
                                hintText: 'Chọn hoặc nhập ngân hàng',
                              ),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxHeight: 300,
                                      maxWidth: MediaQuery.of(context)
                                                  .size
                                                  .width <
                                              600
                                          ? MediaQuery.of(context).size.width -
                                              48
                                          : 400),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        title: Text(option,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                  ),
                  const SizedBox(height: 16),
                  if (isMobileForm) ...[
                    Focus(
                      onFocusChange: (hasFocus) {
                        if (hasFocus &&
                            bankAccountNameController.text.isEmpty &&
                            fullNameController.text.isNotEmpty) {
                          final suggestion = _removeVietnameseAccents(
                                  fullNameController.text)
                              .toUpperCase();
                          setDialogState(() {
                            bankAccountNameController.text = suggestion;
                            bankAccountNameController.selection =
                                TextSelection(
                                    baseOffset: 0,
                                    extentOffset: suggestion.length);
                          });
                        }
                      },
                      child: TextField(
                        controller: bankAccountNameController,
                        decoration: const InputDecoration(
                          labelText: 'Tên chủ tài khoản',
                          prefixIcon: Icon(Icons.person_outline),
                          hintText: 'VD: NGUYEN VAN A',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (value) {
                          final uppercaseValue =
                              _removeVietnameseAccents(value).toUpperCase();
                          if (value != uppercaseValue) {
                            bankAccountNameController.value =
                                TextEditingValue(
                              text: uppercaseValue,
                              selection: TextSelection.collapsed(
                                  offset: uppercaseValue.length),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bankAccountNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Số tài khoản',
                        prefixIcon: Icon(Icons.numbers),
                        hintText: 'VD: 1234567890',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Focus(
                            onFocusChange: (hasFocus) {
                              if (hasFocus &&
                                  bankAccountNameController.text.isEmpty &&
                                  fullNameController.text.isNotEmpty) {
                                final suggestion = _removeVietnameseAccents(
                                        fullNameController.text)
                                    .toUpperCase();
                                setDialogState(() {
                                  bankAccountNameController.text = suggestion;
                                  bankAccountNameController.selection =
                                      TextSelection(
                                          baseOffset: 0,
                                          extentOffset: suggestion.length);
                                });
                              }
                            },
                            child: TextField(
                              controller: bankAccountNameController,
                              decoration: const InputDecoration(
                                labelText: 'Tên chủ tài khoản',
                                prefixIcon: Icon(Icons.person_outline),
                                hintText: 'VD: NGUYEN VAN A',
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onChanged: (value) {
                                // Convert to uppercase without accents
                                final uppercaseValue =
                                    _removeVietnameseAccents(value).toUpperCase();
                                if (value != uppercaseValue) {
                                  bankAccountNameController.value =
                                      TextEditingValue(
                                    text: uppercaseValue,
                                    selection: TextSelection.collapsed(
                                        offset: uppercaseValue.length),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: bankAccountNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Số tài khoản',
                              prefixIcon: Icon(Icons.numbers),
                              hintText: 'VD: 1234567890',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ===== ẢNH CCCD =====
                  _buildSectionHeader('Ảnh CCCD'),
                  Row(
                    children: [
                      // CCCD front
                      _buildImageUploadBox(
                        label: 'CCCD mặt trước',
                        imageUrl: cccdFrontUrl,
                        icon: Icons.credit_card,
                        onPick: () async {
                          final path = await _pickAndCropImage(
                            uploadFn: _apiService.uploadCccdFront,
                            aspectRatio: 1.585,
                          );
                          if (path != null) {
                            setDialogState(() => cccdFrontUrl = path);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      // CCCD back
                      _buildImageUploadBox(
                        label: 'CCCD mặt sau',
                        imageUrl: cccdBackUrl,
                        icon: Icons.credit_card,
                        onPick: () async {
                          final path = await _pickAndCropImage(
                            uploadFn: _apiService.uploadCccdBack,
                            aspectRatio: 1.585,
                          );
                          if (path != null) {
                            setDialogState(() => cccdBackUrl = path);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          Future<Null> onSave() async {
                if (employeeCodeController.text.isEmpty ||
                    fullNameController.text.isEmpty) {
                  _showError('Vui lòng điền đầy đủ thông tin bắt buộc');
                  return;
                }

                Navigator.pop(context);

                // Map work status to int
                int workStatusInt = 0;
                if (selectedWorkStatus == 'Đang làm việc') {
                  workStatusInt = 0;
                } else if (selectedWorkStatus == 'Đang thử việc') {
                  workStatusInt = 3;
                } else if (selectedWorkStatus == 'Nghỉ phép') {
                  workStatusInt = 1;
                } else if (selectedWorkStatus == 'Đã nghỉ việc') {
                  workStatusInt = 2;
                }

                final data = {
                  'employeeCode': employeeCodeController.text,
                  'firstName': fullNameController.text.split(' ').length > 1
                      ? fullNameController.text.split(' ').last
                      : fullNameController.text,
                  'lastName': fullNameController.text.split(' ').length > 1
                      ? fullNameController.text
                          .split(' ')
                          .sublist(
                              0, fullNameController.text.split(' ').length - 1)
                          .join(' ')
                      : '',
                  'phoneNumber': phoneController.text.isNotEmpty
                      ? phoneController.text
                      : null,
                  'personalEmail': emailController.text.isNotEmpty
                      ? emailController.text
                      : null,
                  'companyEmail': companyEmailController.text.isNotEmpty
                      ? companyEmailController.text
                      : '${employeeCodeController.text}@company.com',
                  'gender': selectedGender,
                  'dateOfBirth': selectedDateOfBirth?.toIso8601String(),
                  'nationalIdNumber': nationalIdController.text.isNotEmpty
                      ? nationalIdController.text
                      : null,
                  'permanentAddress': permanentAddressController.text.isNotEmpty
                      ? permanentAddressController.text
                      : null,
                  'temporaryAddress': temporaryAddressController.text.isNotEmpty
                      ? temporaryAddressController.text
                      : null,
                  'emergencyContactPhone':
                      emergencyContactController.text.isNotEmpty
                          ? emergencyContactController.text
                          : null,
                  'emergencyContactName':
                      emergencyContactNameController.text.isNotEmpty
                          ? emergencyContactNameController.text
                          : null,
                  'maritalStatus': selectedMaritalStatus,
                  'hometown': (selectedHometown?.isNotEmpty == true)
                      ? selectedHometown
                      : null,
                  'educationLevel': selectedEducationLevel,
                  'department': departmentController.text.isNotEmpty
                      ? departmentController.text
                      : null,
                  'position': positionController.text.isNotEmpty
                      ? positionController.text
                      : null,
                  'joinDate': selectedJoinDate?.toIso8601String(),
                  'workStatus': workStatusInt,
                  'bankName':
                      selectedBank?.isNotEmpty == true ? selectedBank : null,
                  'bankAccountName': bankAccountNameController.text.isNotEmpty
                      ? bankAccountNameController.text
                      : null,
                  'bankAccountNumber':
                      bankAccountNumberController.text.isNotEmpty
                          ? bankAccountNumberController.text
                          : null,
                  'photoUrl': photoUrl,
                  'idCardFrontUrl': cccdFrontUrl,
                  'idCardBackUrl': cccdBackUrl,
                  'directManagerEmployeeId': selectedManagerId,
                };

                try {
                  bool success;
                  if (isEditing) {
                    success =
                        await _apiService.updateEmployee(employee.id, data);
                  } else {
                    success = await _apiService.createEmployee(data);
                  }

                  if (success) {
                    _showSuccess(isEditing
                        ? 'Đã cập nhật nhân viên'
                        : 'Đã thêm nhân viên mới');
                    await _loadEmployees(showLoading: false);
                  } else {
                    _showError(isEditing
                        ? 'Không thể cập nhật nhân viên'
                        : 'Không thể thêm nhân viên');
                  }
                } catch (e) {
                  _showError('Lỗi: $e');
                }
              }
          if (isMobileForm) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity, height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(isEditing ? _l10n.editEmployee : _l10n.addNewEmployee),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(_l10n.cancel)),
                      const SizedBox(width: 12),
                      ElevatedButton(onPressed: onSave, child: Text(isEditing ? _l10n.save : _l10n.addEmployee)),
                    ]),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: Text(isEditing ? _l10n.editEmployee : _l10n.addNewEmployee),
            content: SizedBox(
              width: MediaQuery.of(context).size.width < 600
                  ? MediaQuery.of(context).size.width - 32
                  : 750,
              height: MediaQuery.of(context).size.height < 750
                  ? MediaQuery.of(context).size.height - 200
                  : 650,
              child: formContent,
            ),
            actions: [
              AppDialogActions(
                onConfirm: onSave,
                confirmLabel: isEditing ? _l10n.save : _l10n.addEmployee,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildImageUploadBox(
      {required String label,
      String? imageUrl,
      required IconData icon,
      required VoidCallback onPick}) {
    return Expanded(
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
          ),
          child: imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                      imageUrl: _apiService.getFileUrl(imageUrl),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => const Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) =>
                          _buildUploadPlaceholder(label, icon)),
                )
              : _buildUploadPlaceholder(label, icon),
        ),
      ),
    );
  }

  Widget _buildUploadPlaceholder(String label, IconData icon) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: Colors.grey[400]),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text('Nhấn để tải lên',
            style: TextStyle(fontSize: 9, color: Colors.grey[400])),
      ],
    );
  }

  Future<Uint8List?> _showCropDialog(Uint8List imageBytes,
      {bool isCircle = false, double? aspectRatio}) async {
    final cropController = CropController();
    Uint8List? croppedBytes;
    final isMobile = Responsive.isMobile(context);

    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cropWidget = Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Crop(
                  image: imageBytes,
                  controller: cropController,
                  onCropped: (result) {
                    switch (result) {
                      case CropSuccess(:final croppedImage):
                        croppedBytes = croppedImage;
                        Navigator.pop(ctx, croppedBytes);
                      case CropFailure(:final cause):
                        debugPrint('Crop failed: $cause');
                        Navigator.pop(ctx, null);
                    }
                  },
                  withCircleUi: isCircle,
                  aspectRatio: isCircle ? 1.0 : aspectRatio,
                  baseColor: Colors.grey[200]!,
                  maskColor: Colors.black.withValues(alpha: 0.5),
                  interactive: true,
                  fixCropRect: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Kéo và thu phóng để chọn vùng ảnh',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        );
        final actionButtons = [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(_l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => cropController.crop(),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Xác nhận'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ];
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity, height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Cắt ảnh'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, null)),
                ),
                body: Padding(padding: const EdgeInsets.all(16), child: cropWidget),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    actionButtons[0],
                    const SizedBox(width: 12),
                    actionButtons[1],
                  ]),
                ),
              ),
            ),
          );
        }
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            children: [
              const Icon(Icons.crop, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              const Text('Cắt ảnh', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx, null)),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 500,
            height: 450,
            child: cropWidget,
          ),
          actions: actionButtons,
        );
      },
    );
  }

  Future<String?> _pickAndCropImage({
    required Future<Map<String, dynamic>> Function(dynamic imageData,
            [String? fileName])
        uploadFn,
    bool isCircle = false,
    double? aspectRatio,
  }) async {
    final images = await pickImagesWithCamera(
      context,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'tiff',
        'tif',
        'heic',
        'heif',
        'avif',
        'jfif',
        'ico',
        'svg'
      ],
    );
    if (images == null || images.isEmpty) return null;

    final bytes = images.first.bytes;
    final fileName = images.first.name;

    // Show crop dialog
    final croppedBytes = await _showCropDialog(Uint8List.fromList(bytes),
        isCircle: isCircle, aspectRatio: aspectRatio);
    if (croppedBytes == null) return null;

    // crop_your_image outputs PNG data, so fix the filename extension
    // to match actual content (avoids backend magic-bytes validation failure)
    String uploadFileName = fileName;
    if (croppedBytes.length >= 4 &&
        croppedBytes[0] == 0x89 &&
        croppedBytes[1] == 0x50 &&
        croppedBytes[2] == 0x4E &&
        croppedBytes[3] == 0x47) {
      final baseName = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      uploadFileName = '$baseName.png';
    }

    // Upload cropped image
    final res = await uploadFn(croppedBytes, uploadFileName);
    if (res['isSuccess'] == true && res['data'] != null) {
      final data = res['data'] as Map<String, dynamic>;
      final path = data['filePath'] ?? data['fileUrl'];
      if (path != null) {
        _showSuccess('Đã tải ảnh lên thành công');
        return path as String;
      }
    }
    
    // Handle error
    String errorMsg = res['message'] ?? 'Không thể tải ảnh lên';
    final statusCode = res['statusCode'];
    if (statusCode == 413) {
      errorMsg = 'Ảnh quá lớn. Vui lòng chọn ảnh nhỏ hơn 5MB.';
    } else if (statusCode == 500) {
      errorMsg = 'Lỗi server khi tải ảnh. Vui lòng thử lại.';
    }
    _showError(errorMsg);
    return null;
  }

  // ignore: unused_element
  Future<String?> _showInputDialog(String title, String label) async {
    final ctrl = TextEditingController();
    final isMobile = Responsive.isMobile(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final field = TextField(
            controller: ctrl,
            decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))));
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity, height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(title),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, null)),
                ),
                body: Padding(padding: const EdgeInsets.all(16), child: field),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(_l10n.cancel)),
                    const SizedBox(width: 12),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Thêm')),
                  ]),
                ),
              ),
            ),
          );
        }
        return AlertDialog(
          title: Text(title),
          content: field,
          actions: [
            AppDialogActions(
              onConfirm: () => Navigator.pop(ctx, ctrl.text),
              confirmLabel: 'Thêm',
            ),
          ],
        );
      },
    );
  }

  void _showEmployeeDetails(Employee employee) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor:
              Theme.of(context).primaryColor.withValues(alpha: 0.2),
          backgroundImage: employee.avatarUrl != null
              ? NetworkImage(_apiService.getFileUrl(employee.avatarUrl!))
              : null,
          onBackgroundImageError: employee.avatarUrl != null ? (_, __) {} : null,
          child: employee.avatarUrl == null
              ? Text(
                  employee.fullName.isNotEmpty
                      ? employee.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employee.fullName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                employee.position ?? 'Nhân viên',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ),
        _buildStatusChip(employee.workStatusDisplay),
      ],
    );

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailSection('Thông tin cơ bản', [
          _buildDetailItem(Icons.badge, 'Mã nhân viên', employee.employeeCode),
          _buildDetailItem(
              Icons.wc,
              'Giới tính',
              employee.genderDisplay.isNotEmpty
                  ? employee.genderDisplay
                  : 'Chưa cập nhật'),
          _buildDetailItem(
            Icons.cake,
            'Ngày sinh',
            employee.dateOfBirth != null
                ? DateFormat('dd/MM/yyyy').format(employee.dateOfBirth!)
                : 'Chưa cập nhật',
          ),
          _buildDetailItem(Icons.credit_card, 'CCCD/CMND',
              employee.nationalId ?? 'Chưa cập nhật'),
          _buildDetailItem(
              Icons.favorite,
              'Tình trạng hôn nhân',
              employee.maritalStatusDisplay.isNotEmpty
                  ? employee.maritalStatusDisplay
                  : 'Chưa cập nhật'),
          _buildDetailItem(Icons.location_city, 'Quê quán',
              employee.hometown ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.school, 'Trình độ học vấn',
              employee.educationLevelDisplay.isNotEmpty
                  ? employee.educationLevelDisplay
                  : 'Chưa cập nhật'),
        ]),
        const SizedBox(height: 16),
        _buildDetailSection('Thông tin liên hệ', [
          _buildDetailItem(
              Icons.phone, 'Số điện thoại', employee.phone ?? 'Chưa cập nhật'),
          _buildDetailItem(
              Icons.email, 'Email cá nhân', employee.email ?? 'Chưa cập nhật'),
          _buildDetailItem(
              Icons.alternate_email, 'Email công ty', employee.companyEmail ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.person_outline, 'Tên người thân',
              employee.emergencyContactName ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.contact_phone, 'SĐT người thân',
              employee.emergencyContact ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.home, 'Thường trú',
              employee.permanentAddress ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.location_on, 'Tạm trú',
              employee.temporaryAddress ?? 'Chưa cập nhật'),
        ]),
        const SizedBox(height: 16),
        _buildDetailSection('Thông tin công việc', [
          _buildDetailItem(Icons.business, 'Phòng ban',
              employee.department ?? 'Chưa cập nhật'),
          _buildDetailItem(
              Icons.work, 'Chức vụ', employee.position ?? 'Chưa cập nhật'),
          _buildDetailItem(
              Icons.info_outline,
              'Trạng thái',
              employee.workStatusDisplay),
          if (employee.managerName != null)
            _buildDetailItem(
                Icons.supervisor_account, 'Quản lý', employee.managerName!),
          _buildDetailItem(
            Icons.calendar_today,
            'Ngày vào làm',
            employee.joinDate != null
                ? DateFormat('dd/MM/yyyy').format(employee.joinDate!)
                : 'Chưa cập nhật',
          ),
        ]),
        const SizedBox(height: 16),
        _buildDetailSection('Thông tin ngân hàng', [
          _buildDetailItem(Icons.account_balance, 'Ngân hàng',
              employee.bankName ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.person_outline, 'Tên tài khoản',
              employee.bankAccountName ?? 'Chưa cập nhật'),
          _buildDetailItem(Icons.numbers, 'Số tài khoản',
              employee.bankAccountNumber ?? 'Chưa cập nhật'),
        ]),
        if (employee.idCardFrontUrl != null ||
            employee.idCardBackUrl != null) ...[
          const SizedBox(height: 16),
          _buildDetailSection('CCCD / Căn cước', [
            if (employee.idCardFrontUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _apiService.getFileUrl(employee.idCardFrontUrl!),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  placeholder: (_, __) => const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                  errorWidget: (_, __, ___) => const SizedBox(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (employee.idCardBackUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _apiService.getFileUrl(employee.idCardBackUrl!),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  placeholder: (_, __) => const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                  errorWidget: (_, __, ___) => const SizedBox(),
                ),
              ),
          ]),
        ],
      ],
    );

    final actionButtons = [
      if (employee.phone != null && employee.phone!.isNotEmpty)
        TextButton.icon(
          onPressed: () => _callEmployee(employee),
          icon: const Icon(Icons.phone, color: Colors.green),
          label: const Text('Gọi điện', style: TextStyle(color: Colors.green)),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
      if (_perm.canEdit(_module))
      ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          _showEmployeeForm(employee);
        },
        icon: const Icon(Icons.edit),
        label: const Text('Chỉnh sửa'),
      ),
    ];

    if (isMobile) {
      showDialog(
        context: context,
        useSafeArea: false,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(employee.fullName, overflow: TextOverflow.ellipsis),
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
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: actionButtons,
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: titleRow,
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: actionButtons,
        ),
      );
    }
  }

  Widget _buildDetailSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...items,
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: Colors.grey[600]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: isMobile ? 100 : 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteEmployee(Employee employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content:
            Text('Bạn có chắc chắn muốn xóa nhân viên "${employee.fullName}"?'),
        actions: [
          AppDialogActions.delete(
            onConfirm: () async {
              Navigator.pop(context);
              final success = await _apiService.deleteEmployee(employee.id);
              if (success) {
                _showSuccess('Đã xóa nhân viên');
                await _loadEmployees(showLoading: false);
              } else {
                _showError('Không thể xóa nhân viên');
              }
            },
          ),
        ],
      ),
    );
  }
}

/// QR Scanner dialog for Vietnamese CCCD (Citizen ID Card)
class _CccdQrScannerDialog extends StatefulWidget {
  const _CccdQrScannerDialog();

  @override
  State<_CccdQrScannerDialog> createState() => _CccdQrScannerDialogState();
}

class _CccdQrScannerDialogState extends State<_CccdQrScannerDialog> {
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  String? _scannedPreview;
  String? _cameraError;
  bool _showManualInput = false;
  final _manualController = TextEditingController();
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: [BarcodeFormat.qrCode],
      );
    } catch (e) {
      setState(() => _cameraError = 'Không thể khởi tạo camera: $e');
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: isMobile ? double.infinity : 420,
        height: _scannedPreview != null || _showManualInput ? 560 : 480,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0C56D0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Quét QR Căn cước công dân',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Scanner view
            Expanded(
              child: _showManualInput
                  ? _buildManualInput()
                  : Stack(
                      children: [
                        if (_scannerController != null)
                          ClipRRect(
                            child: MobileScanner(
                              controller: _scannerController!,
                              errorBuilder: (context, error) {
                                return _buildCameraError(
                                  error.errorDetails?.message ?? 'Không thể truy cập camera',
                                );
                              },
                              onDetect: (capture) {
                                if (_hasScanned) return;
                                final barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty &&
                                    barcodes.first.rawValue != null) {
                                  final code = barcodes.first.rawValue!;
                                  if (code.contains('|')) {
                                    setState(() {
                                      _hasScanned = true;
                                      _scannedPreview = code;
                                    });
                                    Future.delayed(const Duration(milliseconds: 300),
                                        () {
                                      if (context.mounted) Navigator.pop(context, code);
                                    });
                                  }
                                }
                              },
                            ),
                          )
                        else
                          _buildCameraError(_cameraError ?? 'Camera không khả dụng'),
                        // Scan overlay
                        if (_cameraError == null && _scannerController != null)
                          Center(
                            child: Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _hasScanned
                                      ? const Color(0xFF059669)
                                      : Colors.white.withValues(alpha: 0.6),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: _hasScanned
                                  ? const Center(
                                      child: Icon(Icons.check_circle,
                                          color: Color(0xFF059669), size: 48),
                                    )
                                  : null,
                            ),
                          ),
                        // Torch toggle
                        if (_cameraError == null && _scannerController != null && !_hasScanned)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                padding: const EdgeInsets.all(10),
                              ),
                              icon: Icon(
                                _torchOn ? Icons.flash_on : Icons.flash_off,
                                color: _torchOn ? Colors.amber : Colors.white,
                                size: 24,
                              ),
                              onPressed: () {
                                _scannerController?.toggleTorch();
                                setState(() => _torchOn = !_torchOn);
                              },
                            ),
                          ),
                      ],
                    ),
            ),
            // Preview / hint
            Container(
              padding: const EdgeInsets.all(14),
              child: _scannedPreview != null
                  ? Column(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF059669), size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'Đã quét thành công!',
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scannedPreview!.length > 60
                              ? '${_scannedPreview!.substring(0, 60)}...'
                              : _scannedPreview!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF586064), fontSize: 11),
                        ),
                      ],
                    )
                  : _showManualInput
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            const Text(
                              'Hướng camera vào mã QR trên CCCD',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFF586064),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mã QR nằm ở mặt sau của thẻ căn cước',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.grey[400], fontSize: 11),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => setState(() => _showManualInput = true),
                              icon: const Icon(Icons.keyboard, size: 16),
                              label: const Text('Nhập thủ công', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vui lòng kiểm tra:\n• Quyền truy cập camera trong trình duyệt\n• Kết nối qua HTTPS hoặc localhost',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF586064), fontSize: 11),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showManualInput = true),
              icon: const Icon(Icons.keyboard, size: 16),
              label: const Text('Nhập mã thủ công'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C56D0),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code, color: Color(0xFF0C56D0), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Nhập dữ liệu QR CCCD',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Dán nội dung QR đã quét từ ứng dụng khác',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'VD: 079201001234|Nguyen Van A|...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _showManualInput = false),
                child: const Text('Quay lại camera'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  final text = _manualController.text.trim();
                  if (text.isNotEmpty && text.contains('|')) {
                    Navigator.pop(context, text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C56D0),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
