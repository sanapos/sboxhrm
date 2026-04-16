import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get(String key) {
    final map = _localizedValues[locale.languageCode] ?? _localizedValues['vi']!;
    return map[key] ?? _localizedValues['vi']![key] ?? key;
  }

  // Convenience getters for common strings
  // ── Navigation / Sidebar ──
  String get home => get('home');
  String get notifications => get('notifications');
  String get overview => get('overview');
  String get overviewDashboard => get('overviewDashboard');
  String get employeeRecords => get('employeeRecords');
  String get employeeInfo => get('employeeInfo');
  String get deviceUsers => get('deviceUsers');
  String get deviceUsersSubtitle => get('deviceUsersSubtitle');
  String get departments => get('departments');
  String get leave => get('leave');
  String get salarySettings => get('salarySettings');
  String get salaryConfigSubtitle => get('salaryConfigSubtitle');
  String get attendance => get('attendance');
  String get attendanceData => get('attendanceData');
  String get workSchedule => get('workSchedule');
  String get attendanceSummary => get('attendanceSummary');
  String get attendanceByShift => get('attendanceByShift');
  String get attendanceApproval => get('attendanceApproval');
  String get scheduleApproval => get('scheduleApproval');
  String get payrollSummary => get('payrollSummary');
  String get employeePayroll => get('employeePayroll');
  String get bonusPenalty => get('bonusPenalty');
  String get salaryAdvance => get('salaryAdvance');
  String get advanceManagement => get('advanceManagement');
  String get incomeExpense => get('incomeExpense');
  String get assets => get('assets');
  String get tasks => get('tasks');
  String get communication => get('communication');
  String get hrReport => get('hrReport');
  String get hrReportSubtitle => get('hrReportSubtitle');
  String get attendanceReport => get('attendanceReport');
  String get attendanceReportSubtitle => get('attendanceReportSubtitle');
  String get payrollReport => get('payrollReport');
  String get payrollReportSubtitle => get('payrollReportSubtitle');
  String get hrmSetup => get('hrmSetup');
  String get settings => get('settings');
  String get systemAdmin => get('systemAdmin');
  String get licenseKeys => get('licenseKeys');
  String get licenseKeysSubtitle => get('licenseKeysSubtitle');

  // ── Group names ──
  String get groupOverview => get('groupOverview');
  String get groupHrRecords => get('groupHrRecords');
  String get groupAttendance => get('groupAttendance');
  String get groupFinance => get('groupFinance');
  String get groupOperations => get('groupOperations');
  String get groupReports => get('groupReports');
  String get groupAgent => get('groupAgent');
  String get groupSettings => get('groupSettings');
  String get groupOther => get('groupOther');

  // ── Settings screen ──
  String get settingsTitle => get('settingsTitle');
  String get settingsSubtitle => get('settingsSubtitle');
  String get account => get('account');
  String get application => get('application');
  String get darkMode => get('darkMode');
  String get turnedOn => get('turnedOn');
  String get turnedOff => get('turnedOff');
  String get language => get('language');
  String get notificationsLabel => get('notificationsLabel');
  String get connection => get('connection');
  String get autoSync => get('autoSync');
  String get every5Minutes => get('every5Minutes');
  String get information => get('information');
  String get version => get('version');
  String get termsOfUse => get('termsOfUse');
  String get privacyPolicy => get('privacyPolicy');
  String get help => get('help');
  String get logout => get('logout');
  String get selectLanguage => get('selectLanguage');
  String get serverConfig => get('serverConfig');
  String get cancel => get('cancel');
  String get save => get('save');
  String get success => get('success');
  String get serverConfigSaved => get('serverConfigSaved');
  String get logoutConfirm => get('logoutConfirm');
  String get dataManagement => get('dataManagement');
  String get deleteSampleData => get('deleteSampleData');
  String get deleteSampleDataDesc => get('deleteSampleDataDesc');
  String get deleteSampleDataConfirm => get('deleteSampleDataConfirm');
  String get seedSampleData => get('seedSampleData');
  String get seedSampleDataDesc => get('seedSampleDataDesc');
  String get seedSampleDataConfirm => get('seedSampleDataConfirm');

  // ── Common ──
  String get more => get('more');
  String get search => get('search');
  String get goBack => get('goBack');
  String get personalInfo => get('personalInfo');
  String get allFeatures => get('allFeatures');
  String get menu => get('menu');
  String get newNotification => get('newNotification');
  String get face => get('face');
  String get fingerprint => get('fingerprint');
  String get card => get('card');
  String get password => get('password');

  // ── Dashboard ──
  String get sysOverview => get('sysOverview');
  String get refresh => get('refresh');
  String get loadingOverview => get('loadingOverview');
  String get goodMorning => get('goodMorning');
  String get goodAfternoon => get('goodAfternoon');
  String get goodEvening => get('goodEvening');
  String get totalEmployees => get('totalEmployees');
  String get present => get('present');
  String get absent => get('absent');
  String get late => get('late');
  String get attendanceRate => get('attendanceRate');
  String get realtimeAttendance => get('realtimeAttendance');
  String get absentEmployees => get('absentEmployees');
  String get lateEarly => get('lateEarly');
  String get birthday => get('birthday');
  String get todaySchedule => get('todaySchedule');
  String get attendanceTrend7Days => get('attendanceTrend7Days');
  String get byDepartment => get('byDepartment');
  String get topKpiEmployees => get('topKpiEmployees');
  String get kpiToDate => get('kpiToDate');
  String get morningShift => get('morningShift');
  String get afternoonShift => get('afternoonShift');
  String get nightShift => get('nightShift');
  String get authorized => get('authorized');
  String get unauthorized => get('unauthorized');
  String get noSchedule => get('noSchedule');
  String get dayOff => get('dayOff');
  String get scheduled => get('scheduled');
  String get excellent => get('excellent');
  String get good => get('good');
  String get average => get('average');
  String get needsImprovement => get('needsImprovement');
  String get internalNews => get('internalNews');
  String get policy => get('policy');
  String get event => get('event');
  String get checkIn => get('checkIn');
  String get checkOut => get('checkOut');
  String get onlineDevices => get('onlineDevices');
  String get noAttendanceToday => get('noAttendanceToday');
  String get noLateEmployees => get('noLateEmployees');
  String get birthdayThisMonth => get('birthdayThisMonth');
  String get noScheduledToday => get('noScheduledToday');

  // ── Device Users ──
  String get selectDevice => get('selectDevice');
  String get selectDeviceToLoad => get('selectDeviceToLoad');
  String get selectEmployee => get('selectEmployee');
  String get editUser => get('editUser');
  String get editInfo => get('editInfo');
  String get registerFace => get('registerFace');
  String get registerFingerprint => get('registerFingerprint');
  String get reRegisterFace => get('reRegisterFace');
  String get notRegistered => get('notRegistered');
  String get registered => get('registered');
  String get notLinked => get('notLinked');
  String get linked => get('linked');
  String get syncBiometrics => get('syncBiometrics');
  String get deleteAllFingerprints => get('deleteAllFingerprints');
  String get noDeviceConnected => get('noDeviceConnected');
  String get importFromDevice => get('importFromDevice');
  String get uploadHrProfiles => get('uploadHrProfiles');
  String get addUser => get('addUser');
  String get totalUsers => get('totalUsers');
  String get linkedUsers => get('linkedUsers');
  String get unlinkedUsers => get('unlinkedUsers');
  String get user => get('user');
  String get privilege => get('privilege');
  String get deviceName => get('deviceName');
  String get nameOnDevice => get('nameOnDevice');
  String get employeeName => get('employeeName');
  String get cardCode => get('cardCode');
  String get allDevices => get('allDevices');

  // ── Attendance ──
  String get manualAttendance => get('manualAttendance');
  String get autoUpdate => get('autoUpdate');
  String get syncData => get('syncData');
  String get employee => get('employee');
  String get date => get('date');
  String get time => get('time');
  String get note => get('note');
  String get error => get('error');
  String get missingInfo => get('missingInfo');
  String get autoUpdateEnabled => get('autoUpdateEnabled');
  String get autoUpdateDisabled => get('autoUpdateDisabled');
  String get addManualAttendanceSuccess => get('addManualAttendanceSuccess');
  String get device => get('device');
  String get authType => get('authType');
  String get manual => get('manual');
  String get pleaseSelectDevice => get('pleaseSelectDevice');
  String get syncError => get('syncError');
  String get cannotAddAttendance => get('cannotAddAttendance');

  // ── Employees ──
  String get hrManagement => get('hrManagement');
  String get addEmployee => get('addEmployee');
  String get editEmployee => get('editEmployee');
  String get addNewEmployee => get('addNewEmployee');
  String get gender => get('gender');
  String get birthDate => get('birthDate');
  String get phone => get('phone');
  String get address => get('address');
  String get all => get('all');
  String get employeeCode => get('employeeCode');
  String get fullName => get('fullName');
  String get importExcel => get('importExcel');
  String get exportExcel => get('exportExcel');
  String get exportExcelSuccess => get('exportExcelSuccess');
  String get exportExcelFailed => get('exportExcelFailed');
  String get delete => get('delete');
  String get addFirstEmployee => get('addFirstEmployee');
  String get position => get('position');

  // ── Leave ──
  String get leaveManagement => get('leaveManagement');
  String get leaveSubtitle => get('leaveSubtitle');
  String get createRequest => get('createRequest');
  String get pending => get('pending');
  String get approved => get('approved');
  String get rejected => get('rejected');
  String get cancelled => get('cancelled');
  String get annualLeave => get('annualLeave');
  String get unpaidLeave => get('unpaidLeave');
  String get monthlyLeave => get('monthlyLeave');
  String get holidayLeave => get('holidayLeave');
  String get personalPaidLeave => get('personalPaidLeave');
  String get personalUnpaidLeave => get('personalUnpaidLeave');
  String get sickLeave => get('sickLeave');
  String get maternityLeave => get('maternityLeave');
  String get compensatoryLeave => get('compensatoryLeave');
  String get longTermLeave => get('longTermLeave');
  String get myRequests => get('myRequests');
  String get allStatus => get('allStatus');
  String get allTypes => get('allTypes');
  String get today => get('today');
  String get yesterday => get('yesterday');
  String get thisWeek => get('thisWeek');
  String get lastWeek => get('lastWeek');
  String get thisMonth => get('thisMonth');
  String get lastMonth => get('lastMonth');
  String get custom => get('custom');
  String get leaveType => get('leaveType');
  String get leaveDays => get('leaveDays');
  String get shiftLabel => get('shiftLabel');
  String get halfShift => get('halfShift');
  String get reason => get('reason');
  String get status => get('status');
  String get createdAt => get('createdAt');
  String get searchEmployee => get('searchEmployee');
  String get clearFilter => get('clearFilter');
  String get createNewRequest => get('createNewRequest');
  String get noPendingRequests => get('noPendingRequests');
  String get noLeaveRequests => get('noLeaveRequests');

  // ── Payroll ──
  String get payrollShort => get('payrollShort');
  String get payrollTitle => get('payrollTitle');
  String get payrollSubtitle => get('payrollSubtitle');
  String get exportPng => get('exportPng');
  String get selectColumns => get('selectColumns');
  String get columns => get('columns');
  String get standardWorkDays => get('standardWorkDays');
  String get totalWorkDays => get('totalWorkDays');
  String get totalHours => get('totalHours');
  String get overtime => get('overtime');
  String get baseSalary => get('baseSalary');
  String get completionSalary => get('completionSalary');
  String get dailySalary => get('dailySalary');
  String get shiftSalary => get('shiftSalary');
  String get hourSalary => get('hourSalary');
  String get overtimeSalary => get('overtimeSalary');
  String get bonusAmount => get('bonusAmount');
  String get penaltyAmount => get('penaltyAmount');
  String get kpiSalary => get('kpiSalary');
  String get totalSalary => get('totalSalary');
  String get advancePaid => get('advancePaid');
  String get netSalary => get('netSalary');
  String get salaryType => get('salaryType');
  String get hourly => get('hourly');
  String get monthly => get('monthly');
  String get daily => get('daily');
  String get allowance => get('allowance');
  String get salaryProfile => get('salaryProfile');

  // ── Attendance Summary ──
  String get attendanceSummarySubtitle => get('attendanceSummarySubtitle');
  String get requestSentSuccess => get('requestSentSuccess');
  String get requestFailed => get('requestFailed');

  // ── Work Schedule ──
  String get byShift => get('byShift');
  String get pendingSchedule => get('pendingSchedule');
  String get approvedSchedule => get('approvedSchedule');
  String get prevWeek => get('prevWeek');
  String get nextWeek => get('nextWeek');
  String get allDepartments => get('allDepartments');
  String get allEmployees => get('allEmployees');
  String get department => get('department');
  String get copyDay => get('copyDay');
  String get copyWeek => get('copyWeek');
  String get copyMonth => get('copyMonth');
  String get copySchedule => get('copySchedule');
  String get sourceDate => get('sourceDate');
  String get targetDate => get('targetDate');
  String get selectAll => get('selectAll');
  String get deselectAll => get('deselectAll');
  String get applyToAll => get('applyToAll');
  String get copySuccess => get('copySuccess');

  // ── Bonus / Penalty ──
  String get bonus => get('bonus');
  String get penalty => get('penalty');
  String get addNew => get('addNew');
  String get type => get('type');
  String get totalBonus => get('totalBonus');
  String get paid => get('paid');
  String get pendingPayment => get('pendingPayment');
  String get totalPenalty => get('totalPenalty');
  String get penaltyCollected => get('penaltyCollected');
  String get penaltyPending => get('penaltyPending');
  String get edit => get('edit');
  String get approveLabel => get('approveLabel');
  String get payment => get('payment');
  String get collectPenalty => get('collectPenalty');
  String get reverseApproval => get('reverseApproval');
  String get cash => get('cash');
  String get bankTransfer => get('bankTransfer');
  String get eWallet => get('eWallet');
  String get batchApprove => get('batchApprove');
  String get approveAll => get('approveAll');

  // ── Advance Requests ──
  String get payAdvance => get('payAdvance');
  String get paymentMethod => get('paymentMethod');
  String get amount => get('amount');
  String get monthYear => get('monthYear');
  String get requestDate => get('requestDate');
  String get approvedDate => get('approvedDate');
  String get rejectRequest => get('rejectRequest');
  String get rejectReason => get('rejectReason');
  String get deleteRequest => get('deleteRequest');
  String get approvedMsg => get('approvedMsg');
  String get rejectedMsg => get('rejectedMsg');
  String get reversedMsg => get('reversedMsg');
  String get paymentSuccess => get('paymentSuccess');

  // ── Reports ──
  String get generateReport => get('generateReport');
  String get reportType => get('reportType');
  String get dailyReport => get('dailyReport');
  String get monthlyReport => get('monthlyReport');
  String get lateEarlyReport => get('lateEarlyReport');
  String get byDeptReport => get('byDeptReport');
  String get period => get('period');
  String get year => get('year');
  String get from => get('from');
  String get to => get('to');
  String get trend30Days => get('trend30Days');
  String get lateCount => get('lateCount');
  String get excelExported => get('excelExported');
  String get loadError => get('loadError');
  String get exportCsv => get('exportCsv');
  String get clearFilters => get('clearFilters');
  String get totalHeadcount => get('totalHeadcount');
  String get totalBaseSalary => get('totalBaseSalary');
  String get totalGrossSalary => get('totalGrossSalary');
  String get avgBaseSalary => get('avgBaseSalary');
  String get salaryByDept => get('salaryByDept');
  String get salaryDistribution => get('salaryDistribution');
  String get noData => get('noData');
  String get unallocated => get('unallocated');
  String get hrReportSubtitleLong => get('hrReportSubtitleLong');
  String get tenureUnder1Year => get('tenureUnder1Year');
  String get tenure1To3 => get('tenure1To3');
  String get tenure3To5 => get('tenure3To5');
  String get tenure5To10 => get('tenure5To10');
  String get tenureOver10 => get('tenureOver10');
  String get notUpdated => get('notUpdated');
  String get single => get('single');
  String get married => get('married');
  String get female => get('female');
  String get male => get('male');

  // ── Department ──
  String get deptManagement => get('deptManagement');
  String get deptSubtitle => get('deptSubtitle');
  String get list => get('list');
  String get orgChart => get('orgChart');
  String get createFirstDept => get('createFirstDept');
  String get searchDept => get('searchDept');
  String get inactive => get('inactive');
  String get noDept => get('noDept');
  String get noManager => get('noManager');
  String get active => get('active');
  String get stopped => get('stopped');
  String get manager => get('manager');
  String get company => get('company');
  String get noEmployeesInDept => get('noEmployeesInDept');

  // ── Common extras ──
  String get addDept => get('addDept');
  String get edit2 => get('edit2');
  String get approve => get('approve');
  String get reject => get('reject');
  String get close => get('close');
  String get confirm => get('confirm');
  String get loading => get('loading');
  String get noDataAvailable => get('noDataAvailable');
  String get filterBy => get('filterBy');
  String get exportData => get('exportData');
  String get upload => get('upload');
  String get download => get('download');
  String get send => get('send');
  String get back => get('back');
  String get next => get('next');
  String get prev => get('prev');
  String get male2 => get('male');
  String get female2 => get('female');

  static const Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      // Navigation / Sidebar
      'home': 'Trang chủ',
      'notifications': 'Thông báo',
      'overview': 'Tổng quan',
      'overviewDashboard': 'Bảng điều khiển tổng quan',
      'employeeRecords': 'Hồ sơ nhân sự',
      'employeeInfo': 'Thông tin nhân viên, chức vụ',
      'deviceUsers': 'Nhân sự chấm công',
      'deviceUsersSubtitle': 'Nhân sự trên máy chấm công',
      'departments': 'Phòng ban',
      'leave': 'Nghỉ phép',
      'salarySettings': 'Thiết lập lương',
      'salaryConfigSubtitle': 'Cấu hình bảng lương',
      'attendance': 'Chấm công',
      'attendanceData': 'Dữ liệu chấm công',
      'workSchedule': 'Lịch làm việc',
      'attendanceSummary': 'Tổng hợp chấm công',
      'attendanceByShift': 'Tổng hợp theo ca',
      'attendanceApproval': 'Duyệt chấm công',
      'scheduleApproval': 'Duyệt lịch làm việc',
      'payrollSummary': 'Tổng hợp lương',
      'employeePayroll': 'Bảng lương nhân viên',
      'bonusPenalty': 'Thưởng / Phạt',
      'salaryAdvance': 'Ứng lương',
      'advanceManagement': 'Quản lý ứng lương',
      'incomeExpense': 'Thu chi',
      'assets': 'Tài sản',
      'tasks': 'Công việc',
      'communication': 'Truyền thông',
      'hrReport': 'Báo cáo nhân sự',
      'hrReportSubtitle': 'Thống kê nhân sự, phòng ban',
      'attendanceReport': 'Báo cáo chấm công',
      'attendanceReportSubtitle': 'Ngày, tháng, đi muộn, phòng ban',
      'payrollReport': 'Báo cáo lương',
      'payrollReportSubtitle': 'Chi phí lương, phân bổ',
      'hrmSetup': 'Thiết lập HRM',
      'settings': 'Cài đặt',
      'systemAdmin': 'Quản trị hệ thống',
      'licenseKeys': 'License Keys',
      'licenseKeysSubtitle': 'Danh sách key được cấp',

      // Group names
      'groupOverview': 'Tổng quan',
      'groupHrRecords': 'Hồ sơ nhân sự',
      'groupAttendance': 'Chấm công',
      'groupFinance': 'Tài chính',
      'groupOperations': 'Quản lý Vận hành',
      'groupReports': 'Báo cáo',
      'groupAgent': 'Đại lý',
      'groupSettings': 'Cài đặt',
      'groupOther': 'Khác',

      // Settings screen
      'settingsTitle': 'Cài đặt',
      'settingsSubtitle': 'Cấu hình hệ thống và tài khoản',
      'account': 'Tài khoản',
      'application': 'Ứng dụng',
      'darkMode': 'Chế độ tối',
      'turnedOn': 'Đang bật',
      'turnedOff': 'Đang tắt',
      'language': 'Ngôn ngữ',
      'notificationsLabel': 'Thông báo',
      'connection': 'Kết nối',
      'autoSync': 'Đồng bộ tự động',
      'every5Minutes': 'Mỗi 5 phút',
      'information': 'Thông tin',
      'version': 'Phiên bản',
      'termsOfUse': 'Điều khoản sử dụng',
      'privacyPolicy': 'Chính sách bảo mật',
      'help': 'Trợ giúp',
      'logout': 'Đăng xuất',
      'selectLanguage': 'Chọn ngôn ngữ',
      'serverConfig': 'Cấu hình Server',
      'cancel': 'Hủy',
      'save': 'Lưu',
      'success': 'Thành công',
      'serverConfigSaved': 'Đã lưu cấu hình server',
      'logoutConfirm': 'Bạn có chắc chắn muốn đăng xuất?',
      'dataManagement': 'Quản lý dữ liệu',
      'deleteSampleData': 'Xóa dữ liệu mẫu',
      'deleteSampleDataDesc': 'Xóa toàn bộ nhân viên, chấm công, phép... dữ liệu demo',
      'deleteSampleDataConfirm': 'Bạn có chắc chắn muốn xóa toàn bộ dữ liệu mẫu? Hành động này không thể hoàn tác.',
      'seedSampleData': 'Cài dữ liệu mẫu',
      'seedSampleDataDesc': 'Tạo 10 nhân viên, 15 ngày chấm công, phép, tăng ca... để trải nghiệm',
      'seedSampleDataConfirm': 'Bạn có muốn cài dữ liệu mẫu (10 NV, 15 ngày)? Dữ liệu cũ sẽ không bị ảnh hưởng.',

      // Common
      'more': 'Thêm',
      'search': 'Tìm kiếm...',
      'goBack': 'Quay lại',
      'personalInfo': 'Thông tin cá nhân',
      'allFeatures': 'Tất cả chức năng',
      'menu': 'MENU',
      'newNotification': 'Thông báo mới',
      'face': 'Khuôn mặt',
      'fingerprint': 'Vân tay',
      'card': 'Thẻ',
      'password': 'Mật khẩu',

      // Dashboard
      'sysOverview': 'Tổng quan hệ thống',
      'refresh': 'Làm mới',
      'loadingOverview': 'Đang tải dữ liệu tổng quan...',
      'goodMorning': 'Chào buổi sáng',
      'goodAfternoon': 'Chào buổi chiều',
      'goodEvening': 'Chào buổi tối',
      'totalEmployees': 'Tổng nhân viên',
      'present': 'Có mặt',
      'absent': 'Vắng mặt',
      'late': 'Đi trễ',
      'attendanceRate': 'Tỉ lệ CC',
      'realtimeAttendance': 'Chấm công thời gian thực',
      'absentEmployees': 'Nhân viên vắng mặt',
      'lateEarly': 'Đi trễ / Về sớm',
      'birthday': 'Sinh nhật',
      'todaySchedule': 'Lịch làm việc hôm nay',
      'attendanceTrend7Days': 'Xu hướng chấm công 7 ngày',
      'byDepartment': 'Thống kê theo phòng ban',
      'topKpiEmployees': 'Top nhân viên KPI',
      'kpiToDate': 'KPI đến hôm nay',
      'morningShift': 'Ca sáng',
      'afternoonShift': 'Ca chiều',
      'nightShift': 'Ca đêm',
      'authorized': 'Có phép',
      'unauthorized': 'Không phép',
      'noSchedule': 'Không có lịch',
      'dayOff': 'Nghỉ/Trống',
      'scheduled': 'Xếp lịch',
      'excellent': 'Xuất sắc',
      'good': 'Tốt',
      'average': 'Trung bình',
      'needsImprovement': 'Cần cải thiện',
      'internalNews': 'Bản tin nội bộ',
      'policy': 'Chính sách',
      'event': 'Sự kiện',
      'checkIn': 'Check-in',
      'checkOut': 'Check-out',
      'onlineDevices': 'TB Online',
      'noAttendanceToday': 'Chưa có dữ liệu chấm công hôm nay',
      'noLateEmployees': 'Không có nhân viên đi trễ / về sớm',
      'birthdayThisMonth': 'Trong tháng',
      'noScheduledToday': 'Không có lịch làm việc hôm nay',

      // Device Users
      'selectDevice': 'Chọn máy chấm công',
      'selectDeviceToLoad': 'Chọn máy để tải danh sách nhân viên:',
      'selectEmployee': 'Chọn nhân viên',
      'editUser': 'Chỉnh sửa user',
      'editInfo': 'Chỉnh sửa thông tin',
      'registerFace': 'Đăng ký khuôn mặt',
      'registerFingerprint': 'Đăng ký vân tay',
      'reRegisterFace': 'Đăng ký lại khuôn mặt',
      'notRegistered': 'Chưa đăng ký',
      'registered': 'Đã đăng ký',
      'notLinked': 'Chưa liên kết',
      'linked': 'Đã liên kết',
      'syncBiometrics': 'Đồng bộ sinh trắc học',
      'deleteAllFingerprints': 'Xóa tất cả vân tay',
      'noDeviceConnected': 'Chưa có máy chấm công nào được kết nối',
      'importFromDevice': 'Tải từ máy',
      'uploadHrProfiles': 'Tải hồ sơ NS',
      'addUser': 'Thêm user',
      'totalUsers': 'Tổng user',
      'linkedUsers': 'Đã liên kết',
      'unlinkedUsers': 'Chưa liên kết',
      'user': 'Quyền',
      'privilege': 'Quyền',
      'deviceName': 'Tên thiết bị',
      'nameOnDevice': 'Tên trong máy',
      'employeeName': 'Tên nhân viên',
      'cardCode': 'Mã thẻ từ',
      'allDevices': 'Tất cả thiết bị',

      // Attendance
      'manualAttendance': 'Chấm công thủ công',
      'autoUpdate': 'Tự động cập nhật',
      'syncData': 'Đồng bộ dữ liệu',
      'employee': 'Nhân viên',
      'date': 'Ngày',
      'time': 'Giờ',
      'note': 'Ghi chú',
      'error': 'Lỗi',
      'missingInfo': 'Thiếu thông tin',
      'autoUpdateEnabled': 'Đã bật tự động cập nhật (10 giây/lần)',
      'autoUpdateDisabled': 'Đã tắt tự động cập nhật',
      'addManualAttendanceSuccess': 'Đã thêm chấm công thủ công',
      'device': 'Thiết bị',
      'authType': 'Kiểu xác thực',
      'manual': 'Thủ công',
      'pleaseSelectDevice': 'Vui lòng chọn ít nhất một thiết bị',
      'syncError': 'Lỗi đồng bộ',
      'cannotAddAttendance': 'Không thể thêm chấm công',

      // Employees
      'hrManagement': 'Quản lý nhân sự',
      'addEmployee': 'Thêm nhân viên',
      'editEmployee': 'Chỉnh sửa nhân viên',
      'addNewEmployee': 'Thêm nhân viên mới',
      'gender': 'Giới tính',
      'birthDate': 'Ngày sinh',
      'phone': 'Số điện thoại',
      'address': 'Địa chỉ',
      'all': 'Tất cả',
      'employeeCode': 'Mã NV',
      'fullName': 'Họ tên',
      'importExcel': 'Nhập Excel',
      'exportExcel': 'Xuất Excel',
      'exportExcelSuccess': 'Xuất Excel thành công!',
      'exportExcelFailed': 'Xuất Excel thất bại',
      'delete': 'Xóa',
      'addFirstEmployee': 'Thêm nhân viên mới để bắt đầu',
      'position': 'Chức vụ',

      // Leave
      'leaveManagement': 'Quản lý nghỉ phép',
      'leaveSubtitle': 'Tạo, theo dõi và duyệt đơn nghỉ phép',
      'createRequest': 'Tạo đơn',
      'pending': 'Chờ duyệt',
      'approved': 'Đã duyệt',
      'rejected': 'Từ chối',
      'cancelled': 'Đã hủy',
      'annualLeave': 'Phép năm',
      'unpaidLeave': 'Không lương',
      'monthlyLeave': 'Theo tháng',
      'holidayLeave': 'Lễ tết',
      'personalPaidLeave': 'VR có lương',
      'personalUnpaidLeave': 'VR không lương',
      'sickLeave': 'Ốm đau',
      'maternityLeave': 'Thai sản',
      'compensatoryLeave': 'Nghỉ bù',
      'longTermLeave': 'Nghỉ dài hạn',
      'myRequests': 'Đơn của tôi',
      'allStatus': 'Tất cả TT',
      'allTypes': 'Tất cả loại',
      'today': 'Hôm nay',
      'yesterday': 'Hôm qua',
      'thisWeek': 'Tuần này',
      'lastWeek': 'Tuần trước',
      'thisMonth': 'Tháng này',
      'lastMonth': 'Tháng trước',
      'custom': 'Tùy chọn...',
      'leaveType': 'Loại nghỉ',
      'leaveDays': 'Ngày nghỉ',
      'shiftLabel': 'Ca nghỉ',
      'halfShift': 'Nửa ca',
      'reason': 'Lý do',
      'status': 'Trạng thái',
      'createdAt': 'Ngày tạo',
      'searchEmployee': 'Tìm nhân viên...',
      'clearFilter': 'Xóa lọc',
      'createNewRequest': 'Tạo đơn mới',
      'noPendingRequests': 'Không có đơn chờ duyệt',
      'noLeaveRequests': 'Chưa có đơn nghỉ phép nào',

      // Payroll
      'payrollShort': 'Lương',
      'payrollTitle': 'Tổng hợp lương',
      'payrollSubtitle': 'Bảng lương chi tiết nhân viên',
      'exportPng': 'Xuất PNG',
      'selectColumns': 'Chọn cột',
      'columns': 'Cột',
      'standardWorkDays': 'Công chuẩn',
      'totalWorkDays': 'Tổng công',
      'totalHours': 'Tổng giờ',
      'overtime': 'Tăng ca',
      'baseSalary': 'Lương cơ bản',
      'completionSalary': 'Lương hoàn thành',
      'dailySalary': 'Lương theo ngày',
      'shiftSalary': 'Lương theo ca',
      'hourSalary': 'Lương theo giờ',
      'overtimeSalary': 'Lương tăng ca',
      'bonusAmount': 'Thưởng',
      'penaltyAmount': 'Phạt',
      'kpiSalary': 'Lương KPI',
      'totalSalary': 'Tổng lương',
      'advancePaid': 'Ứng lương',
      'netSalary': 'Thực nhận',
      'salaryType': 'Loại lương',
      'hourly': 'Giờ',
      'monthly': 'Tháng',
      'daily': 'Ngày',
      'allowance': 'Phụ cấp',
      'salaryProfile': 'Hồ sơ lương',

      // Attendance Summary
      'attendanceSummarySubtitle': 'Tổng hợp dữ liệu chấm công theo nhân viên và ngày',
      'requestSentSuccess': 'Đã gửi yêu cầu chấm công thành công',
      'requestFailed': 'Gửi yêu cầu thất bại. Vui lòng thử lại.',

      // Work Schedule
      'byShift': 'Theo ca làm việc',
      'pendingSchedule': 'Lịch làm việc - Đăng ký chờ duyệt',
      'approvedSchedule': 'Lịch làm việc đã duyệt',
      'prevWeek': 'Tuần trước',
      'nextWeek': 'Tuần sau',
      'allDepartments': 'Tất cả phòng ban',
      'allEmployees': 'Tất cả nhân viên',
      'department': 'Phòng ban',
      'copyDay': 'Sao chép ngày',
      'copyWeek': 'Sao chép tuần',
      'copyMonth': 'Sao chép tháng',
      'copySchedule': 'Sao chép lịch:',
      'sourceDate': 'Ngày nguồn:',
      'targetDate': 'Ngày đích',
      'selectAll': 'Chọn tất cả',
      'deselectAll': 'Bỏ chọn tất cả',
      'applyToAll': 'Áp dụng cho tất cả nhân viên',
      'copySuccess': 'Sao chép thành công',

      // Bonus / Penalty
      'bonus': 'Thưởng',
      'penalty': 'Phạt',
      'addNew': 'Thêm mới',
      'type': 'Loại',
      'totalBonus': 'Tổng thưởng',
      'paid': 'Đã thanh toán',
      'pendingPayment': 'Chờ thanh toán',
      'totalPenalty': 'Tổng phạt',
      'penaltyCollected': 'Đã thu phạt',
      'penaltyPending': 'Chưa thu phạt',
      'edit': 'Sửa',
      'approveLabel': 'Duyệt',
      'payment': 'Thanh toán',
      'collectPenalty': 'Thu tiền phạt',
      'reverseApproval': 'Hoàn duyệt',
      'cash': 'Tiền mặt',
      'bankTransfer': 'Chuyển khoản',
      'eWallet': 'Ví điện tử',
      'batchApprove': 'Duyệt hàng loạt',
      'approveAll': 'Duyệt tất cả',

      // Advance Requests
      'payAdvance': 'Thanh toán ứng lương',
      'paymentMethod': 'Phương thức thanh toán',
      'amount': 'Số tiền (VNĐ)',
      'monthYear': 'Tháng/Năm',
      'requestDate': 'Ngày yêu cầu',
      'approvedDate': 'Ngày duyệt',
      'rejectRequest': 'Từ chối yêu cầu',
      'rejectReason': 'Lý do từ chối',
      'deleteRequest': 'Xóa yêu cầu',
      'approvedMsg': 'Đã duyệt yêu cầu',
      'rejectedMsg': 'Đã từ chối yêu cầu',
      'reversedMsg': 'Đã hoàn duyệt yêu cầu',
      'paymentSuccess': 'Đã thanh toán và tạo phiếu chi',

      // Reports
      'generateReport': 'Tạo báo cáo',
      'reportType': 'Loại báo cáo',
      'dailyReport': 'Hàng ngày',
      'monthlyReport': 'Hàng tháng',
      'lateEarlyReport': 'Đi muộn/về sớm',
      'byDeptReport': 'Theo phòng ban',
      'period': 'Thời gian',
      'year': 'Năm',
      'from': 'Từ',
      'to': 'Đến',
      'trend30Days': 'Xu hướng chấm công 30 ngày',
      'lateCount': 'Đi muộn',
      'excelExported': 'Đã xuất Excel',
      'loadError': 'Lỗi tải dữ liệu',
      'exportCsv': 'Xuất CSV',
      'clearFilters': 'Xóa bộ lọc',
      'totalHeadcount': 'Tổng nhân sự',
      'totalBaseSalary': 'Tổng lương cơ bản',
      'totalGrossSalary': 'Tổng lương gộp',
      'avgBaseSalary': 'TB lương cơ bản',
      'salaryByDept': 'Chi phí lương theo phòng ban',
      'salaryDistribution': 'Phân bổ mức lương',
      'noData': 'Không có dữ liệu',
      'unallocated': 'Chưa phân bổ',
      'hrReportSubtitleLong': 'Tổng hợp thông tin nhân sự & phân tích',
      'tenureUnder1Year': 'Dưới 1 năm',
      'tenure1To3': '1-3 năm',
      'tenure3To5': '3-5 năm',
      'tenure5To10': '5-10 năm',
      'tenureOver10': 'Trên 10 năm',
      'notUpdated': 'Chưa cập nhật',
      'single': 'Độc thân',
      'married': 'Đã kết hôn',
      'female': 'Nữ',
      'male': 'Nam',

      // Department
      'deptManagement': 'Quản lý Phòng ban',
      'deptSubtitle': 'Thiết lập cấu trúc tổ chức công ty',
      'list': 'Danh sách',
      'orgChart': 'Sơ đồ tổ chức',
      'createFirstDept': 'Tạo phòng ban đầu tiên',
      'searchDept': 'Tìm kiếm theo mã hoặc tên phòng ban...',
      'inactive': 'Hiện không hoạt động',
      'noDept': 'Chưa có phòng ban nào',
      'noManager': 'Chưa có quản lý',
      'active': 'Hoạt động',
      'stopped': 'Ngừng hoạt động',
      'manager': 'Quản lý',
      'company': 'CÔNG TY',
      'noEmployeesInDept': 'Chưa có nhân viên trong phòng ban này',

      // Common extras
      'addDept': 'Thêm mới',
      'edit2': 'Chỉnh sửa',
      'approve': 'Duyệt',
      'reject': 'Từ chối',
      'close': 'Đóng',
      'confirm': 'Xác nhận',
      'loading': 'Đang tải...',
      'noDataAvailable': 'Chưa có dữ liệu',
      'filterBy': 'Lọc theo',
      'exportData': 'Xuất dữ liệu',
      'upload': 'Tải lên',
      'download': 'Tải xuống',
      'send': 'Gửi',
      'back': 'Quay lại',
      'next': 'Tiếp',
      'prev': 'Trước',
    },
    'en': {
      // Navigation / Sidebar
      'home': 'Home',
      'notifications': 'Notifications',
      'overview': 'Overview',
      'overviewDashboard': 'Overview dashboard',
      'employeeRecords': 'Employee Records',
      'employeeInfo': 'Employee info, positions',
      'deviceUsers': 'Device Users',
      'deviceUsersSubtitle': 'Staff on attendance devices',
      'departments': 'Departments',
      'leave': 'Leave',
      'salarySettings': 'Salary Settings',
      'salaryConfigSubtitle': 'Payroll configuration',
      'attendance': 'Attendance',
      'attendanceData': 'Attendance data',
      'workSchedule': 'Work Schedule',
      'attendanceSummary': 'Attendance Summary',
      'attendanceByShift': 'Summary by Shift',
      'attendanceApproval': 'Attendance Approval',
      'scheduleApproval': 'Schedule Approval',
      'payrollSummary': 'Payroll Summary',
      'employeePayroll': 'Employee payroll table',
      'bonusPenalty': 'Bonus / Penalty',
      'salaryAdvance': 'Salary Advance',
      'advanceManagement': 'Advance management',
      'incomeExpense': 'Income / Expense',
      'assets': 'Assets',
      'tasks': 'Tasks',
      'communication': 'Communication',
      'hrReport': 'HR Report',
      'hrReportSubtitle': 'HR & department statistics',
      'attendanceReport': 'Attendance Report',
      'attendanceReportSubtitle': 'Daily, monthly, late, by department',
      'payrollReport': 'Payroll Report',
      'payrollReportSubtitle': 'Salary costs, allocation',
      'hrmSetup': 'HRM Setup',
      'settings': 'Settings',
      'systemAdmin': 'System Admin',
      'licenseKeys': 'License Keys',
      'licenseKeysSubtitle': 'Assigned key list',

      // Group names
      'groupOverview': 'Overview',
      'groupHrRecords': 'HR Records',
      'groupAttendance': 'Attendance',
      'groupFinance': 'Finance',
      'groupOperations': 'Operations',
      'groupReports': 'Reports',
      'groupAgent': 'Agent',
      'groupSettings': 'Settings',
      'groupOther': 'Other',

      // Settings screen
      'settingsTitle': 'Settings',
      'settingsSubtitle': 'System & account configuration',
      'account': 'Account',
      'application': 'Application',
      'darkMode': 'Dark Mode',
      'turnedOn': 'On',
      'turnedOff': 'Off',
      'language': 'Language',
      'notificationsLabel': 'Notifications',
      'connection': 'Connection',
      'autoSync': 'Auto Sync',
      'every5Minutes': 'Every 5 minutes',
      'information': 'Information',
      'version': 'Version',
      'termsOfUse': 'Terms of Use',
      'privacyPolicy': 'Privacy Policy',
      'help': 'Help',
      'logout': 'Logout',
      'selectLanguage': 'Select Language',
      'serverConfig': 'Server Configuration',
      'cancel': 'Cancel',
      'save': 'Save',
      'success': 'Success',
      'serverConfigSaved': 'Server configuration saved',
      'logoutConfirm': 'Are you sure you want to logout?',
      'dataManagement': 'Data Management',
      'deleteSampleData': 'Delete Sample Data',
      'deleteSampleDataDesc': 'Remove all demo employees, attendance, leave data...',
      'deleteSampleDataConfirm': 'Are you sure you want to delete all sample data? This action cannot be undone.',
      'seedSampleData': 'Install Sample Data',
      'seedSampleDataDesc': 'Create 10 employees, 15 days of attendance, leave, overtime... to explore',
      'seedSampleDataConfirm': 'Do you want to install sample data (10 employees, 15 days)? Existing data will not be affected.',

      // Common
      'more': 'More',
      'search': 'Search...',
      'goBack': 'Go back',
      'personalInfo': 'Personal Info',
      'allFeatures': 'All Features',
      'menu': 'MENU',
      'newNotification': 'New notification',
      'face': 'Face',
      'fingerprint': 'Fingerprint',
      'card': 'Card',
      'password': 'Password',

      // Dashboard
      'sysOverview': 'System Overview',
      'refresh': 'Refresh',
      'loadingOverview': 'Loading overview data...',
      'goodMorning': 'Good morning',
      'goodAfternoon': 'Good afternoon',
      'goodEvening': 'Good evening',
      'totalEmployees': 'Total Employees',
      'present': 'Present',
      'absent': 'Absent',
      'late': 'Late',
      'attendanceRate': 'Att. Rate',
      'realtimeAttendance': 'Real-time Attendance',
      'absentEmployees': 'Absent Employees',
      'lateEarly': 'Late / Early Leave',
      'birthday': 'Birthday',
      'todaySchedule': "Today's Schedule",
      'attendanceTrend7Days': '7-Day Attendance Trend',
      'byDepartment': 'Stats by Department',
      'topKpiEmployees': 'Top KPI Employees',
      'kpiToDate': 'KPI to Date',
      'morningShift': 'Morning Shift',
      'afternoonShift': 'Afternoon Shift',
      'nightShift': 'Night Shift',
      'authorized': 'Authorized',
      'unauthorized': 'Unauthorized',
      'noSchedule': 'No Schedule',
      'dayOff': 'Day Off',
      'scheduled': 'Scheduled',
      'excellent': 'Excellent',
      'good': 'Good',
      'average': 'Average',
      'needsImprovement': 'Needs Improvement',
      'internalNews': 'Internal News',
      'policy': 'Policy',
      'event': 'Event',
      'checkIn': 'Check-in',
      'checkOut': 'Check-out',
      'onlineDevices': 'Online Devices',
      'noAttendanceToday': 'No attendance data for today',
      'noLateEmployees': 'No late/early-leave employees',
      'birthdayThisMonth': 'This month',
      'noScheduledToday': 'No work schedule for today',

      // Device Users
      'selectDevice': 'Select Device',
      'selectDeviceToLoad': 'Select device to load employee list:',
      'selectEmployee': 'Select Employee',
      'editUser': 'Edit User',
      'editInfo': 'Edit Info',
      'registerFace': 'Register Face',
      'registerFingerprint': 'Register Fingerprint',
      'reRegisterFace': 'Re-register Face',
      'notRegistered': 'Not Registered',
      'registered': 'Registered',
      'notLinked': 'Not Linked',
      'linked': 'Linked',
      'syncBiometrics': 'Sync Biometrics',
      'deleteAllFingerprints': 'Delete All Fingerprints',
      'noDeviceConnected': 'No device connected',
      'importFromDevice': 'Import from Device',
      'uploadHrProfiles': 'Upload HR Profiles',
      'addUser': 'Add User',
      'totalUsers': 'Total Users',
      'linkedUsers': 'Linked',
      'unlinkedUsers': 'Unlinked',
      'user': 'Privilege',
      'privilege': 'Privilege',
      'deviceName': 'Device Name',
      'nameOnDevice': 'Name on Device',
      'employeeName': 'Employee Name',
      'cardCode': 'Card Code',
      'allDevices': 'All Devices',

      // Attendance
      'manualAttendance': 'Manual Attendance',
      'autoUpdate': 'Auto Update',
      'syncData': 'Sync Data',
      'employee': 'Employee',
      'date': 'Date',
      'time': 'Time',
      'note': 'Note',
      'error': 'Error',
      'missingInfo': 'Missing info',
      'autoUpdateEnabled': 'Auto update enabled (10 sec interval)',
      'autoUpdateDisabled': 'Auto update disabled',
      'addManualAttendanceSuccess': 'Manual attendance added',
      'device': 'Device',
      'authType': 'Auth Type',
      'manual': 'Manual',
      'pleaseSelectDevice': 'Please select at least one device',
      'syncError': 'Sync error',
      'cannotAddAttendance': 'Cannot add attendance',

      // Employees
      'hrManagement': 'HR Management',
      'addEmployee': 'Add Employee',
      'editEmployee': 'Edit Employee',
      'addNewEmployee': 'Add New Employee',
      'gender': 'Gender',
      'birthDate': 'Date of Birth',
      'phone': 'Phone Number',
      'address': 'Address',
      'all': 'All',
      'employeeCode': 'Emp. Code',
      'fullName': 'Full Name',
      'importExcel': 'Import Excel',
      'exportExcel': 'Export Excel',
      'exportExcelSuccess': 'Excel exported successfully!',
      'exportExcelFailed': 'Export Excel failed',
      'delete': 'Delete',
      'addFirstEmployee': 'Add a new employee to get started',
      'position': 'Position',

      // Leave
      'leaveManagement': 'Leave Management',
      'leaveSubtitle': 'Create, track and approve leave requests',
      'createRequest': 'Create Request',
      'pending': 'Pending',
      'approved': 'Approved',
      'rejected': 'Rejected',
      'cancelled': 'Cancelled',
      'annualLeave': 'Annual',
      'unpaidLeave': 'Unpaid',
      'monthlyLeave': 'Monthly',
      'holidayLeave': 'Holiday',
      'personalPaidLeave': 'Personal Paid',
      'personalUnpaidLeave': 'Personal Unpaid',
      'sickLeave': 'Sick',
      'maternityLeave': 'Maternity',
      'compensatoryLeave': 'Compensatory',
      'longTermLeave': 'Long-term',
      'myRequests': 'My Requests',
      'allStatus': 'All Status',
      'allTypes': 'All Types',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'thisWeek': 'This Week',
      'lastWeek': 'Last Week',
      'thisMonth': 'This Month',
      'lastMonth': 'Last Month',
      'custom': 'Custom...',
      'leaveType': 'Leave Type',
      'leaveDays': 'Leave Days',
      'shiftLabel': 'Shift',
      'halfShift': 'Half Shift',
      'reason': 'Reason',
      'status': 'Status',
      'createdAt': 'Created At',
      'searchEmployee': 'Search employee...',
      'clearFilter': 'Clear Filter',
      'createNewRequest': 'Create New Request',
      'noPendingRequests': 'No pending requests',
      'noLeaveRequests': 'No leave requests yet',

      // Payroll
      'payrollShort': 'Payroll',
      'payrollTitle': 'Payroll Summary',
      'payrollSubtitle': 'Employee payroll detail table',
      'exportPng': 'Export PNG',
      'selectColumns': 'Select Columns',
      'columns': 'Columns',
      'standardWorkDays': 'Std. Days',
      'totalWorkDays': 'Work Days',
      'totalHours': 'Total Hours',
      'overtime': 'Overtime',
      'baseSalary': 'Base Salary',
      'completionSalary': 'Completion Salary',
      'dailySalary': 'Daily Salary',
      'shiftSalary': 'Shift Salary',
      'hourSalary': 'Hourly Salary',
      'overtimeSalary': 'OT Salary',
      'bonusAmount': 'Bonus',
      'penaltyAmount': 'Penalty',
      'kpiSalary': 'KPI Salary',
      'totalSalary': 'Total Salary',
      'advancePaid': 'Advance',
      'netSalary': 'Net Salary',
      'salaryType': 'Salary Type',
      'hourly': 'Hourly',
      'monthly': 'Monthly',
      'daily': 'Daily',
      'allowance': 'Allowance',
      'salaryProfile': 'Salary Profile',

      // Attendance Summary
      'attendanceSummarySubtitle': 'Attendance data summary by employee and date',
      'requestSentSuccess': 'Attendance request sent successfully',
      'requestFailed': 'Request failed. Please try again.',

      // Work Schedule
      'byShift': 'By Shift',
      'pendingSchedule': 'Work Schedule - Pending Approval',
      'approvedSchedule': 'Approved Schedule',
      'prevWeek': 'Previous Week',
      'nextWeek': 'Next Week',
      'allDepartments': 'All Departments',
      'allEmployees': 'All Employees',
      'department': 'Department',
      'copyDay': 'Copy Day',
      'copyWeek': 'Copy Week',
      'copyMonth': 'Copy Month',
      'copySchedule': 'Copy Schedule:',
      'sourceDate': 'Source Date:',
      'targetDate': 'Target Date',
      'selectAll': 'Select All',
      'deselectAll': 'Deselect All',
      'applyToAll': 'Apply to All Employees',
      'copySuccess': 'Copy Successful',

      // Bonus / Penalty
      'bonus': 'Bonus',
      'penalty': 'Penalty',
      'addNew': 'Add New',
      'type': 'Type',
      'totalBonus': 'Total Bonus',
      'paid': 'Paid',
      'pendingPayment': 'Pending Payment',
      'totalPenalty': 'Total Penalty',
      'penaltyCollected': 'Collected',
      'penaltyPending': 'Pending Collection',
      'edit': 'Edit',
      'approveLabel': 'Approve',
      'payment': 'Payment',
      'collectPenalty': 'Collect Penalty',
      'reverseApproval': 'Reverse Approval',
      'cash': 'Cash',
      'bankTransfer': 'Bank Transfer',
      'eWallet': 'E-Wallet',
      'batchApprove': 'Batch Approve',
      'approveAll': 'Approve All',

      // Advance Requests
      'payAdvance': 'Pay Advance',
      'paymentMethod': 'Payment Method',
      'amount': 'Amount (VND)',
      'monthYear': 'Month/Year',
      'requestDate': 'Request Date',
      'approvedDate': 'Approved Date',
      'rejectRequest': 'Reject Request',
      'rejectReason': 'Rejection Reason',
      'deleteRequest': 'Delete Request',
      'approvedMsg': 'Request approved',
      'rejectedMsg': 'Request rejected',
      'reversedMsg': 'Approval reversed',
      'paymentSuccess': 'Payment made, expense voucher created',

      // Reports
      'generateReport': 'Generate Report',
      'reportType': 'Report Type',
      'dailyReport': 'Daily',
      'monthlyReport': 'Monthly',
      'lateEarlyReport': 'Late / Early Leave',
      'byDeptReport': 'By Department',
      'period': 'Period',
      'year': 'Year',
      'from': 'From',
      'to': 'To',
      'trend30Days': '30-Day Attendance Trend',
      'lateCount': 'Late',
      'excelExported': 'Exported to Excel',
      'loadError': 'Data load error',
      'exportCsv': 'Export CSV',
      'clearFilters': 'Clear Filters',
      'totalHeadcount': 'Total Headcount',
      'totalBaseSalary': 'Total Base Salary',
      'totalGrossSalary': 'Total Gross Salary',
      'avgBaseSalary': 'Avg Base Salary',
      'salaryByDept': 'Salary Cost by Dept',
      'salaryDistribution': 'Salary Distribution',
      'noData': 'No Data',
      'unallocated': 'Unallocated',
      'hrReportSubtitleLong': 'HR information summary & analysis',
      'tenureUnder1Year': 'Under 1 year',
      'tenure1To3': '1-3 years',
      'tenure3To5': '3-5 years',
      'tenure5To10': '5-10 years',
      'tenureOver10': 'Over 10 years',
      'notUpdated': 'Not updated',
      'single': 'Single',
      'married': 'Married',
      'female': 'Female',
      'male': 'Male',

      // Department
      'deptManagement': 'Department Management',
      'deptSubtitle': 'Set up company organizational structure',
      'list': 'List',
      'orgChart': 'Org Chart',
      'createFirstDept': 'Create first department',
      'searchDept': 'Search by code or department name...',
      'inactive': 'Currently inactive',
      'noDept': 'No departments yet',
      'noManager': 'No manager assigned',
      'active': 'Active',
      'stopped': 'Stopped',
      'manager': 'Manager',
      'company': 'COMPANY',
      'noEmployeesInDept': 'No employees in this department',

      // Common extras
      'addDept': 'Add New',
      'edit2': 'Edit',
      'approve': 'Approve',
      'reject': 'Reject',
      'close': 'Close',
      'confirm': 'Confirm',
      'loading': 'Loading...',
      'noDataAvailable': 'No data available',
      'filterBy': 'Filter by',
      'exportData': 'Export',
      'upload': 'Upload',
      'download': 'Download',
      'send': 'Send',
      'back': 'Back',
      'next': 'Next',
      'prev': 'Previous',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['vi', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
