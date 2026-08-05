/// Module code groups aligned with backend ModulePermissionImplicitGrants.
class PermissionModules {
  PermissionModules._();

  /// Luôn cho phép xem — cài đặt cá nhân, trang chủ, thông báo.
  static const selfServiceModules = {
    'Home',
    'Notification',
    'Settings',
  };

  /// Màn duyệt — menu/route chỉ mở khi có quyền Duyệt, không alias từ Xem lịch/chỉnh công.
  static const approvalNavModules = {
    'AttendanceApproval',
    'ScheduleApproval',
    'MobileAttendanceApproval',
  };

  /// Menu chỉ hiện khi module được cấp trực tiếp — không alias chéo (Thu chi, Phiếu thưởng…).
  static const explicitNavModules = {
    'CashTransaction',
    'Transaction',
    'BonusPenalty',
    'BankAccount',
    'CashReport',
    'AdvanceRequests',
    'BusinessTripExpense',
    'PenaltyTickets',
    'Production',
    'PosProducts',
    'PosSalesReport',
    'ProductSalary',
    'KPI',
    'LeaveReport',
    'PenaltyReport',
    'AttendanceReport',
    'AdvanceReport',
    'BusinessTripReport',
    'AssetReport',
  };

  static const financialTransactions = [
    'Transaction',
    'CashTransaction',
    'BonusPenalty',
  ];

  static const attendanceRead = [
    'Attendance',
    'AttendanceSummary',
    'AttendanceByShift',
    'LateEarlyReport',
  ];

  static const attendanceApproval = [
    'AttendanceApproval',
    'AttendanceCorrection',
  ];

  static const scheduleApproval = [
    'ScheduleApproval',
    'WorkSchedule',
  ];

  static const shiftSetup = [
    'ShiftSetup',
    'ShiftTemplate',
    'Shift',
  ];

  /// Khớp backend PayrollReadModules — cần quyền Payroll mới được xem.
  static const payrollRead = [
    'Employee',
    'Attendance',
    'AttendanceSummary',
    'AttendanceByShift',
    'Leave',
    'SalarySettings',
    'Insurance',
    'Tax',
    'PenaltySetup',
    'Allowance',
    'Holiday',
    'AdvanceRequests',
    'Transaction',
    'PenaltyTickets',
    'KPI',
    'Production',
    'ShiftSalaryLevel',
    'WorkSchedule',
    'ShiftSetup',
    'Benefit',
    'BonusPenalty',
    'SystemSettings',
  ];

  static const reportModules = [
    'LeaveReport',
    'CashReport',
    'PenaltyReport',
    'AttendanceReport',
    'AdvanceReport',
    'BusinessTripReport',
    'AssetReport',
    'Report',
  ];

  /// Nhân viên: quyền xem Đăng ký chấm công Mobile → dùng được Chấm công Mobile.
  static const mobileAttendanceFromDeviceRegistration = 'MobileDeviceRegistration';

  static const mobileAttendanceFromApproval = 'MobileAttendanceApproval';
}
