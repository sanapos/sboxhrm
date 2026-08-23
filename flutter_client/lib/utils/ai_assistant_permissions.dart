import '../providers/permission_provider.dart';

/// Maps AI [[ACTION:...]] / [[CREATE:...]] tags to app module permissions.
class AiAssistantPermissions {
  AiAssistantPermissions._();

  static const _actionRules = <String, _Rule>{
    'nav_dashboard': _Rule('Dashboard', create: false),
    'nav_attendance': _Rule('Attendance', create: false),
    'nav_attendance_history': _Rule('Attendance', create: false),
    'nav_leave': _Rule('Leave', create: false),
    'nav_leave_create': _Rule('Leave', create: true),
    'nav_payroll': _Rule('Payslip', create: false),
    'nav_payslip': _Rule('Payslip', create: false),
    'nav_kpi': _Rule('KPI', create: false),
    'nav_communication': _Rule('Communication', create: false),
    'nav_meal': _Rule('Meal', create: false),
    'nav_meal_register': _Rule('Meal', create: true),
    'nav_tasks': _Rule('Task', create: false),
    'nav_assets': _Rule('Asset', create: false),
    'nav_cash': _Rule('CashTransaction', create: false),
    'nav_bonus_penalty': _Rule('BonusPenalty', create: false),
    'nav_advance': _Rule('AdvanceRequests', create: false),
    'nav_advance_create': _Rule('AdvanceRequests', create: true),
    'nav_overtime': _Rule('Overtime', create: false),
    'nav_overtime_create': _Rule('Overtime', create: true),
    'nav_field_checkin': _Rule('FieldCheckIn', create: false),
    'nav_field_checkin_create': _Rule('FieldCheckIn', create: true),
    'nav_attendance_correction': _Rule('AttendanceCorrection', create: false),
    'nav_attendance_correction_create':
        _Rule('AttendanceCorrection', create: true),
    'nav_work_schedule': _Rule('WorkSchedule', create: false),
    'nav_shift_change': _Rule('ShiftSwap', create: true),
    'nav_feedback': _Rule('Feedback', create: false),
    'nav_feedback_create': _Rule('Feedback', create: true),
    'nav_employees': _Rule('Employee', create: false),
    'nav_departments': _Rule('Department', create: false),
    'nav_business_trip': _Rule('BusinessTripExpense', create: false),
    'nav_business_trip_create': _Rule('BusinessTripExpense', create: true),
    'nav_penalty': _Rule('PenaltyTickets', create: false),
    'nav_production': _Rule('Production', create: false),
    'nav_mobile_attendance': _Rule('MobileAttendance', create: false),
    'nav_schedule_approval': _Rule('ScheduleApproval', create: false),
    'nav_leave_report': _Rule('LeaveReport', create: false),
    'nav_cash_report': _Rule('CashReport', create: false),
    'nav_advance_report': _Rule('AdvanceReport', create: false),
    'nav_business_trip_report': _Rule('BusinessTripReport', create: false),
    'nav_attendance_summary': _Rule('AttendanceSummary', create: false),
    'nav_penalty_report': _Rule('PenaltyReport', create: false),
    'nav_pos_sell': _Rule('PosSell', create: false),
    'nav_pos_reports': _Rule('PosSalesReport', create: false),
    'nav_pos_products': _Rule('PosProducts', create: false),
    'nav_pos_printers': _Rule('PosPrinters', create: false),
  };

  static const _createRules = <String, _Rule>{
    'attendance_correction': _Rule('AttendanceCorrection', create: true),
    'leave': _Rule('Leave', create: true),
    'advance': _Rule('AdvanceRequests', create: true),
    'feedback': _Rule('Feedback', create: true),
    'meal': _Rule('Meal', create: true),
    'field_assignment': _Rule('FieldCheckIn', create: true),
    'shift_swap': _Rule('ShiftSwap', create: true),
    'overtime': _Rule('Overtime', create: true),
    'business_trip': _Rule('BusinessTripExpense', create: true),
  };

  static bool canAction(String action, PermissionProvider perm) {
    final rule = _actionRules[action];
    if (rule == null) return false;
    return rule.allows(perm);
  }

  static bool canCreate(String createTag, PermissionProvider perm) {
    final type = createTag.split(',').first.trim();
    final rule = _createRules[type];
    if (rule == null) return false;
    return rule.allows(perm);
  }

  static String deniedMessageForAction(String action) {
    final rule = _actionRules[action];
    if (rule == null) return 'Tài khoản không có quyền thực hiện thao tác này.';
    return rule.create
        ? 'Tài khoản không có quyền tạo mới trên module ${rule.module}.'
        : 'Tài khoản không có quyền xem module ${rule.module}.';
  }

  static String deniedMessageForCreate(String createTag) {
    final type = createTag.split(',').first.trim();
    final rule = _createRules[type];
    if (rule == null) {
      return 'Tài khoản không có quyền tạo loại phiếu này.';
    }
    return 'Tài khoản không có quyền tạo trên module ${rule.module}.';
  }

  /// Module codes the user may view (for optional UI hints).
  static List<String> viewableModules(PermissionProvider perm) {
    const modules = [
      'Dashboard',
      'Attendance',
      'Leave',
      'Payslip',
      'KPI',
      'Communication',
      'Meal',
      'Task',
      'Asset',
      'CashTransaction',
      'BonusPenalty',
      'AdvanceRequests',
      'Overtime',
      'FieldCheckIn',
      'AttendanceCorrection',
      'WorkSchedule',
      'ShiftSwap',
      'Feedback',
      'Employee',
      'Department',
      'BusinessTripExpense',
      'PenaltyTickets',
      'Production',
      'MobileAttendance',
      'ScheduleApproval',
      'LeaveReport',
      'CashReport',
      'AdvanceReport',
      'BusinessTripReport',
      'AttendanceSummary',
      'PenaltyReport',
      'PosSell',
      'PosSalesReport',
      'PosProducts',
      'PosPrinters',
    ];
    return modules.where((m) => perm.canView(m)).toList();
  }
}

class _Rule {
  final String module;
  final bool create;

  const _Rule(this.module, {required this.create});

  bool allows(PermissionProvider perm) {
    return create ? perm.canCreate(module) : perm.canView(module);
  }
}
