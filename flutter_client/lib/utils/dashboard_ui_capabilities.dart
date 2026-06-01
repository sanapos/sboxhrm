import '../providers/permission_provider.dart';
import 'dashboard_access.dart';
import 'dashboard_permission_modules.dart';

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
  }) {
    if (DashboardAccess.useEmployeeDashboard(perm, role: role)) {
      return const DashboardUiCapabilities(
        useEmployeeLayout: true,
        showQuickActions: true,
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
        loadLeaves: true,
        loadSchedules: false,
        loadPendingApprovals: false,
        loadTasks: false,
        loadOvertime: false,
        loadPenalty: false,
        loadCash: false,
        loadContracts: false,
        loadAdvances: false,
        loadBirthdays: false,
        quickLeave: true,
        quickShiftSwap: true,
        quickPayroll: true,
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

    final hero = _w(perm, DashboardPermissionModules.attendanceOverview);
    final insights = _w(perm, DashboardPermissionModules.hrInsights);
    final shiftSched = _w(perm, DashboardPermissionModules.todaySchedule);
    final gridRealtime =
        _w(perm, DashboardPermissionModules.realtimeAttendance);
    final gridAbsent = _w(perm, DashboardPermissionModules.absent);
    final gridLate = _w(perm, DashboardPermissionModules.lateEarly);
    final gridKpi = _w(perm, DashboardPermissionModules.kpiPanel);
    final gridNews = _w(perm, DashboardPermissionModules.internalNews);
    final mainGrid =
        gridRealtime || gridAbsent || gridLate || gridKpi || gridNews;
    final emp = perm.canView('Employee');

    return DashboardUiCapabilities(
      useEmployeeLayout: false,
      showQuickActions: perm.canView('Leave') ||
          perm.canView('ScheduleApproval') ||
          perm.canView('ShiftSwap') ||
          perm.canView('Payroll') ||
          perm.canView('Payslip') ||
          perm.canView('Communication') ||
          perm.canView('AIGemini'),
      showAttendanceHero: hero,
      showShiftSchedule: shiftSched,
      showInsightSection: insights,
      showMainGrid: mainGrid,
      showAiFab: perm.canView('AIGemini'),
      loadDailyReport: hero,
      loadDevices: hero || gridRealtime || perm.canView('Device'),
      loadEmployees: emp && (hero || gridAbsent || insights),
      loadRawAttendances: hero || gridRealtime || gridLate,
      loadCommunications: gridNews || perm.canView('Communication'),
      loadKpi: gridKpi || perm.canView('KPI'),
      loadLeaves: insights && perm.canView('Leave'),
      loadSchedules: shiftSched,
      loadPendingApprovals: insights && _pendingModules(perm),
      loadTasks: insights && perm.canView('Task'),
      loadOvertime: insights && perm.canView('Overtime'),
      loadPenalty: insights &&
          (perm.canView('PenaltyTickets') || perm.canView('BonusPenalty')),
      loadCash: insights && perm.canView('CashTransaction'),
      loadContracts: insights && emp,
      loadAdvances: insights && perm.canView('AdvanceRequests'),
      loadBirthdays: insights && emp,
      quickLeave: perm.canView('Leave'),
      quickShiftSwap:
          perm.canView('ScheduleApproval') || perm.canView('ShiftSwap'),
      quickPayroll: perm.canView('Payroll') || perm.canView('Payslip'),
      quickCommunication: perm.canView('Communication'),
      quickAi: perm.canView('AIGemini'),
      insightLeave: insights,
      insightPending: insights && _pendingModules(perm),
      insightBirthday: insights && emp,
      insightOvertime: insights && perm.canView('Overtime'),
      insightTask: insights && perm.canView('Task'),
      insightPenalty: insights &&
          (perm.canView('PenaltyTickets') || perm.canView('BonusPenalty')),
      insightContracts: insights && emp,
      insightAdvance: insights && perm.canView('AdvanceRequests'),
      insightNewHires: insights && emp,
      insightCash: insights && perm.canView('CashTransaction'),
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
