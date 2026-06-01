/// Module code groups aligned with backend ModulePermissionImplicitGrants.
class PermissionModules {
  PermissionModules._();

  static const financialTransactions = [
    'Transaction',
    'CashTransaction',
    'BonusPenalty',
  ];

  static const attendanceRead = [
    'Attendance',
    'AttendanceSummary',
    'AttendanceByShift',
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

  static const payrollRead = [
    'Payroll',
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
    'BonusPenalty',
    'SystemSettings',
  ];

  static const reportModules = [
    'LeaveReport',
    'CashReport',
    'PenaltyReport',
    'AdvanceReport',
    'AssetReport',
    'Report',
  ];
}
