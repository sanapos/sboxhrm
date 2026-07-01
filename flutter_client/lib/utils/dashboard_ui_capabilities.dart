import '../providers/permission_provider.dart';
import 'dashboard_access.dart';
import 'dashboard_permission_modules.dart';
import 'permission_navigation.dart';

/// Quyết định block nào trên Dashboard được render / gọi API.
class DashboardUiCapabilities {
  final bool useEmployeeLayout;
  final bool showQuickActions;
  final bool showAttendanceHero;
  final bool showShiftSchedule;
  final bool showInsightSection;
  final bool showMainGrid;
  final bool showAiFab;

  final bool loadDailyReport;
  final bool loadDevices;
  final bool loadEmployees;
  final bool loadRawAttendances;
  final bool loadCommunications;
  final bool loadKpi;
  final bool loadLeaves;
  final bool loadSchedules;
  final bool loadPendingApprovals;
  final bool loadTasks;
  final bool loadOvertime;
  final bool loadPenalty;
  final bool loadCash;
  final bool loadContracts;
  final bool loadAdvances;
  final bool loadBirthdays;

  final bool quickLeave;
  final bool quickShiftSwap;
  final bool quickPayroll;
  final bool quickCommunication;
  final bool quickAi;

  final bool insightLeave;
  final bool insightPending;
  final bool insightBirthday;
  final bool insightOvertime;
  final bool insightTask;
  final bool insightPenalty;
  final bool insightContracts;
  final bool insightAdvance;
  final bool insightNewHires;
  final bool insightCash;

  final bool gridRealtime;
  final bool gridAbsent;
  final bool gridLateEarly;
  final bool gridKpi;
  final bool gridNews;

  const DashboardUiCapabilities({
    required this.useEmployeeLayout,
    required this.showQuickActions,
    required this.showAttendanceHero,
    required this.showShiftSchedule,
    required this.showInsightSection,
    required this.showMainGrid,
    required this.showAiFab,
    required this.loadDailyReport,
    required this.loadDevices,
    required this.loadEmployees,
    required this.loadRawAttendances,
    required this.loadCommunications,
    required this.loadKpi,
    required this.loadLeaves,
    required this.loadSchedules,
    required this.loadPendingApprovals,
    required this.loadTasks,
    required this.loadOvertime,
    required this.loadPenalty,
    required this.loadCash,
    required this.loadContracts,
    required this.loadAdvances,
    required this.loadBirthdays,
    required this.quickLeave,
    required this.quickShiftSwap,
    required this.quickPayroll,
    required this.quickCommunication,
    required this.quickAi,
    required this.insightLeave,
    required this.insightPending,
    required this.insightBirthday,
    required this.insightOvertime,
    required this.insightTask,
    required this.insightPenalty,
    required this.insightContracts,
    required this.insightAdvance,
    required this.insightNewHires,
    required this.insightCash,
    required this.gridRealtime,
    required this.gridAbsent,
    required this.gridLateEarly,
    required this.gridKpi,
    required this.gridNews,
  });

  static bool _w(PermissionProvider p, String code) =>
      DashboardPermissionModules.canViewWidget(p, code);

  static bool _pendingModules(PermissionProvider p) =>
      (p.canView('Leave') && p.canApprove('Leave')) ||
      (p.canView('AttendanceApproval') &&
          p.canApprove('AttendanceApproval')) ||
      (p.canView('ScheduleApproval') && p.canApprove('ScheduleApproval')) ||
      (p.canView('AdvanceRequests') && p.canApprove('AdvanceRequests'));

  factory DashboardUiCapabilities.from(
    PermissionProvider perm, {
    String? role,
    List<String>? allowedModules,
  }) {
    bool pkg(String code) => PermissionNavigation.canAccessModule(
          code,
          allowedModules: allowedModules,
          perm: perm,
          role: role,
        );

    if (DashboardAccess.useEmployeeDashboard(perm, role: role)) {
      final quickLeave = pkg('Leave') && perm.canView('Leave');
      final quickShiftSwap = (pkg('ShiftSwap') && perm.canView('ShiftSwap')) ||
          (pkg('ScheduleApproval') && perm.canApprove('ScheduleApproval'));
      final quickPayroll = (pkg('Payslip') && perm.canView('Payslip')) ||
          (pkg('Payroll') && perm.canView('Payroll'));
      return DashboardUiCapabilities(
        useEmployeeLayout: true,
        showQuickActions:
            quickLeave || quickShiftSwap || quickPayroll,
        showAttendanceHero: false,
        showShiftSchedule: false,
        showInsightSection: false,
        showMainGrid: false,
        showAiFab: false,
        loadDailyReport: false,
        loadDevices: false,
        loadEmployees: false,
        loadRawAttendances: false,
        loadCommunications: false,
        loadKpi: false,
        loadLeaves: quickLeave,
        loadSchedules: false,
        loadPendingApprovals: false,
        loadTasks: false,
        loadOvertime: false,
        loadPenalty: false,
        loadCash: false,
        loadContracts: false,
        loadAdvances: false,
        loadBirthdays: false,
        quickLeave: quickLeave,
        quickShiftSwap: quickShiftSwap,
        quickPayroll: quickPayroll,
        quickCommunication: false,
        quickAi: false,
        insightLeave: false,
        insightPending: false,
        insightBirthday: false,
        insightOvertime: false,
        insightTask: false,
        insightPenalty: false,
        insightContracts: false,
        insightAdvance: false,
        insightNewHires: false,
        insightCash: false,
        gridRealtime: false,
        gridAbsent: false,
        gridLateEarly: false,
        gridKpi: false,
        gridNews: false,
      );
    }

    final hero = _w(perm, DashboardPermissionModules.attendanceOverview) &&
        pkg('Attendance');
    final insights =
        _w(perm, DashboardPermissionModules.hrInsights) && pkg('Dashboard');
    final shiftSched =
        _w(perm, DashboardPermissionModules.todaySchedule) &&
            pkg('WorkSchedule');
    final gridRealtime = _w(perm, DashboardPermissionModules.realtimeAttendance) &&
        pkg('Attendance');
    final gridAbsent =
        _w(perm, DashboardPermissionModules.absent) && pkg('Employee');
    final gridLate =
        _w(perm, DashboardPermissionModules.lateEarly) && pkg('Attendance');
    final gridKpi = _w(perm, DashboardPermissionModules.kpiPanel) && pkg('KPI');
    final gridNews =
        _w(perm, DashboardPermissionModules.internalNews) &&
            pkg('Communication');
    final mainGrid =
        gridRealtime || gridAbsent || gridLate || gridKpi || gridNews;
    final emp = pkg('Employee') && perm.canView('Employee');

    return DashboardUiCapabilities(
      useEmployeeLayout: false,
      showQuickActions: (pkg('Leave') && perm.canView('Leave')) ||
          (pkg('ScheduleApproval') && perm.canApprove('ScheduleApproval')) ||
          (pkg('ShiftSwap') && perm.canView('ShiftSwap')) ||
          (pkg('Payroll') && perm.canView('Payroll')) ||
          (pkg('Payslip') && perm.canView('Payslip')) ||
          (pkg('Communication') && perm.canView('Communication')) ||
          (pkg('AIGemini') && perm.canView('AIGemini')),
      showAttendanceHero: hero,
      showShiftSchedule: shiftSched,
      showInsightSection: insights,
      showMainGrid: mainGrid,
      showAiFab: pkg('AIGemini') && perm.canView('AIGemini'),
      loadDailyReport: hero,
      loadDevices: (hero || gridRealtime || perm.canView('Device')) &&
          pkg('Device'),
      loadEmployees: emp && (hero || gridAbsent || insights),
      loadRawAttendances: hero || gridRealtime || gridLate,
      loadCommunications: (gridNews || perm.canView('Communication')) &&
          pkg('Communication'),
      loadKpi: (gridKpi || perm.canView('KPI')) && pkg('KPI'),
      loadLeaves: insights && pkg('Leave') && perm.canView('Leave'),
      loadSchedules: shiftSched,
      loadPendingApprovals: insights && _pendingModules(perm),
      loadTasks: insights && pkg('Task') && perm.canView('Task'),
      loadOvertime: insights && pkg('Overtime') && perm.canView('Overtime'),
      loadPenalty: insights &&
          pkg('BonusPenalty') &&
          (perm.canView('PenaltyTickets') || perm.canView('BonusPenalty')),
      loadCash: insights &&
          pkg('CashTransaction') &&
          perm.canView('CashTransaction'),
      loadContracts: insights && emp,
      loadAdvances: insights &&
          pkg('AdvanceRequests') &&
          perm.canView('AdvanceRequests'),
      loadBirthdays: insights && emp,
      quickLeave: pkg('Leave') && perm.canView('Leave'),
      quickShiftSwap: (pkg('ScheduleApproval') &&
              perm.canApprove('ScheduleApproval')) ||
          (pkg('ShiftSwap') && perm.canView('ShiftSwap')),
      quickPayroll: (pkg('Payroll') && perm.canView('Payroll')) ||
          (pkg('Payslip') && perm.canView('Payslip')),
      quickCommunication:
          pkg('Communication') && perm.canView('Communication'),
      quickAi: pkg('AIGemini') && perm.canView('AIGemini'),
      insightLeave: insights,
      insightPending: insights && _pendingModules(perm),
      insightBirthday: insights && emp,
      insightOvertime: insights && pkg('Overtime') && perm.canView('Overtime'),
      insightTask: insights && pkg('Task') && perm.canView('Task'),
      insightPenalty: insights &&
          pkg('BonusPenalty') &&
          (perm.canView('PenaltyTickets') || perm.canView('BonusPenalty')),
      insightContracts: insights && emp,
      insightAdvance: insights &&
          pkg('AdvanceRequests') &&
          perm.canView('AdvanceRequests'),
      insightNewHires: insights && emp,
      insightCash: insights &&
          pkg('CashTransaction') &&
          perm.canView('CashTransaction'),
      gridRealtime: gridRealtime,
      gridAbsent: gridAbsent,
      gridLateEarly: gridLate,
      gridKpi: gridKpi,
      gridNews: gridNews,
    );
  }

  bool get isOverviewOnly =>
      !useEmployeeLayout &&
      !showAttendanceHero &&
      !showShiftSchedule &&
      !showInsightSection &&
      !showMainGrid;
}
