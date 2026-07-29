import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/permission_provider.dart';
import '../../screens/overtime_screen.dart';
import '../../utils/navigation_notifier.dart';
import '../../widgets/hrm_pushed_screen_shell.dart';
import '../pos/pos_mobile_widgets.dart';
import '../hrm_page_chrome.dart';
import '../safe_layout_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class EmployeeModuleGrid extends StatelessWidget {
  const EmployeeModuleGrid({super.key});

  static const _order = [
    'MobileAttendance',
    'Leave',
    'Payslip',
    'Payroll',
    'ShiftSwap',
    'WorkSchedule',
    'Attendance',
    'AttendanceByShift',
    'AttendanceSummary',
    'Overtime',
    'AdvanceRequests',
    'BonusPenalty',
    'PenaltyTickets',
    'Task',
    'Communication',
    'Feedback',
    'KPI',
    'Production',
    'FieldCheckIn',
    'Meal',
    'MobileDeviceRegistration',
    'Notification',
  ];

  static const _meta = <String, ({IconData icon, String label, Color color})>{
    'MobileAttendance': (
      icon: Icons.phone_android_outlined,
      label: 'Chấm công',
      color: Color(0xFF0284C7),
    ),
    'Leave': (
      icon: Icons.beach_access_outlined,
      label: 'Nghỉ phép',
      color: Color(0xFFF59E0B),
    ),
    'Payslip': (
      icon: Icons.receipt_long_outlined,
      label: 'Phiếu lương',
      color: Color(0xFF06B6D4),
    ),
    'Payroll': (
      icon: Icons.payments_outlined,
      label: 'Bảng lương',
      color: Color(0xFF7C3AED),
    ),
    'ShiftSwap': (
      icon: Icons.swap_horiz_outlined,
      label: 'Đổi ca',
      color: Color(0xFF8B5CF6),
    ),
    'WorkSchedule': (
      icon: Icons.calendar_month_outlined,
      label: 'Lịch làm việc',
      color: Color(0xFF2D5F8B),
    ),
    'Attendance': (
      icon: Icons.access_time_outlined,
      label: 'Chấm công thô',
      color: Color(0xFF0284C7),
    ),
    'AttendanceByShift': (
      icon: Icons.view_week_outlined,
      label: 'Tổng hợp theo ca',
      color: Color(0xFF7C3AED),
    ),
    'AttendanceSummary': (
      icon: Icons.summarize_outlined,
      label: 'Tổng hợp công',
      color: Color(0xFF7C3AED),
    ),
    'Overtime': (
      icon: Icons.more_time_outlined,
      label: 'Tăng ca',
      color: Color(0xFFEA580C),
    ),
    'AdvanceRequests': (
      icon: Icons.money_outlined,
      label: 'Ứng lương',
      color: Color(0xFFEC4899),
    ),
    'BonusPenalty': (
      icon: Icons.card_giftcard_outlined,
      label: 'Thưởng / phạt',
      color: Color(0xFFEC4899),
    ),
    'PenaltyTickets': (
      icon: Icons.receipt_outlined,
      label: 'Phiếu phạt',
      color: Color(0xFFEF4444),
    ),
    'Task': (
      icon: Icons.task_alt_outlined,
      label: 'Công việc',
      color: Color(0xFF059669),
    ),
    'Communication': (
      icon: Icons.campaign_outlined,
      label: 'Truyền thông',
      color: Color(0xFFEC4899),
    ),
    'Feedback': (
      icon: Icons.feedback_outlined,
      label: 'Phản ánh',
      color: HrmPageChrome.primaryNavy,
    ),
    'KPI': (
      icon: Icons.trending_up_outlined,
      label: 'KPI',
      color: Color(0xFF059669),
    ),
    'Production': (
      icon: Icons.precision_manufacturing_outlined,
      label: 'Sản lượng',
      color: Color(0xFF059669),
    ),
    'FieldCheckIn': (
      icon: Icons.map_outlined,
      label: 'Bản đồ NS',
      color: Color(0xFF059669),
    ),
    'Meal': (
      icon: Icons.restaurant_outlined,
      label: 'Chấm cơm',
      color: Color(0xFF059669),
    ),
    'MobileDeviceRegistration': (
      icon: Icons.app_registration_outlined,
      label: 'Đăng ký thiết bị',
      color: Color(0xFF0284C7),
    ),
    'Notification': (
      icon: Icons.notifications_outlined,
      label: 'Thông báo',
      color: HrmPageChrome.primaryNavy,
    ),
  };

  static String? _labelFor(String code, AppLocalizations l) {
    switch (code) {
      case 'MobileAttendance':
        return 'Chấm công';
      case 'Leave':
        return l.leave;
      case 'Payslip':
        return 'Phiếu lương';
      case 'Payroll':
        return l.payrollSummary;
      case 'ShiftSwap':
        return 'Đổi ca';
      case 'WorkSchedule':
        return l.workSchedule;
      case 'Attendance':
        return l.attendance;
      case 'AttendanceByShift':
        return l.attendanceByShift;
      case 'AttendanceSummary':
        return l.attendanceSummary;
      case 'Overtime':
        return 'Tăng ca';
      case 'AdvanceRequests':
        return l.salaryAdvance;
      case 'BonusPenalty':
        return l.bonusPenalty;
      case 'PenaltyTickets':
        return 'Phiếu phạt';
      case 'Task':
        return l.tasks;
      case 'Communication':
        return l.communication;
      case 'Feedback':
        return 'Phản ánh';
      case 'KPI':
        return 'KPI';
      case 'Production':
        return 'Sản lượng';
      case 'FieldCheckIn':
        return 'Bản đồ nhân sự';
      case 'Meal':
        return 'Chấm cơm';
      case 'MobileDeviceRegistration':
        return 'Đăng ký thiết bị';
      case 'Notification':
        return l.notifications;
      default:
        return null;
    }
  }

  static List<_EmployeeModuleTile> _visibleModules(
    PermissionProvider perm,
    AppLocalizations l,
  ) {
    final tiles = <_EmployeeModuleTile>[];
    var seenPay = false;

    for (final code in _order) {
      if (code == 'Payroll' && perm.canView('Payslip')) continue;
      if (code == 'Payslip' || code == 'Payroll') {
        if (seenPay) continue;
        if (!perm.canView('Payslip') && !perm.canView('Payroll')) continue;
        final usePayslip = perm.canView('Payslip');
        final payCode = usePayslip ? 'Payslip' : 'Payroll';
        final meta = _meta[payCode]!;
        tiles.add(_EmployeeModuleTile(
          moduleCode: payCode,
          icon: meta.icon,
          label: _labelFor(payCode, l) ?? meta.label,
          color: meta.color,
        ));
        seenPay = true;
        continue;
      }

      if (code == 'Overtime') {
        if (!perm.canView('Overtime')) continue;
      } else if (!perm.canView(code)) {
        continue;
      }

      final meta = _meta[code];
      if (meta == null) continue;
      tiles.add(_EmployeeModuleTile(
        moduleCode: code,
        icon: meta.icon,
        label: _labelFor(code, l) ?? meta.label,
        color: meta.color,
      ));
    }
    return tiles;
  }

  static void _openModule(BuildContext context, _EmployeeModuleTile tile) {
    if (tile.moduleCode == 'Overtime') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const HrmPushedScreenShell(
            title: 'Quản lý tăng ca',
            child: OvertimeScreen(),
          ),
        ),
      );
      return;
    }
    NavigationNotifier.goToModule(tile.moduleCode);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final perm = Provider.of<PermissionProvider>(context);
    final tiles = _visibleModules(perm, l);
    if (tiles.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 768;

    if (isMobile) {
      return PosMobileHubSectionGrid(
        title: 'Chức năng',
        items: tiles
            .map(
              (tile) => PosMobileHubGridItem(
                label: tile.label,
                icon: tile.icon,
                onTap: () => _openModule(context, tile),
              ),
            )
            .toList(),
      );
    }

    final crossAxisCount = width >= 1024 ? 4 : (width >= 600 ? 3 : 2);
    const spacing = 10.0;
    const childAspectRatio = 1.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Chức năng'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF18181B),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        SafeFixedGrid(
          crossAxisCount: crossAxisCount,
          spacing: spacing,
          runSpacing: spacing,
          childAspectRatio: childAspectRatio,
          itemCount: tiles.length,
          itemBuilder: (context, i) {
            final tile = tiles[i];
            return _ModuleTile(
              tile: tile,
              onTap: () => _openModule(context, tile),
            );
          },
        ),
      ],
    );
  }
}

class _EmployeeModuleTile {
  final String moduleCode;
  final IconData icon;
  final String label;
  final Color color;

  const _EmployeeModuleTile({
    required this.moduleCode,
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _ModuleTile extends StatelessWidget {
  final _EmployeeModuleTile tile;
  final VoidCallback onTap;

  const _ModuleTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tile.color.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: tile.color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        tile.color,
                        Color.lerp(tile.color, Colors.white, 0.35)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(tile.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(tile.label),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3F3F46),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
