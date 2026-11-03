import 'package:flutter/material.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/deferred_screen.dart';
import '../advance_requests_screen.dart';
import '../attendance_corrections_screen.dart';
import '../business_trip_expense_screen.dart';
import '../comm/comm_hub_screen.dart' deferred as comm_hub;
import '../feedback_screen.dart';
import '../hr_finance/hr_finance_hub_screen.dart';
import '../leave_screen.dart';
import '../meal_tracking_screen.dart';
import '../mobile_attendance_history_screen.dart';
import '../mobile_attendance_screen.dart';
import '../mobile_device_registration_screen.dart';
import '../overtime_screen.dart';
import '../payslip_screen.dart';
import '../shift_swap_screen.dart';
import '../work/work_hub_screen.dart';
import 'staff_nav.dart';

/// Danh mục chức năng của app SBOX Nhân Viên — dùng lại màn HRM sẵn có, mã module
/// trùng menu [MainLayout] để quyền / gói dịch vụ áp đúng như app quản trị.
abstract final class StaffEntries {
  static final punch = StaffEntry(
    moduleCode: 'MobileAttendance',
    title: 'Chấm công',
    subtitle: 'Chấm trên điện thoại',
    icon: Icons.fingerprint,
    color: SboxColors.primary,
    builder: (_) => const MobileAttendanceScreen(),
  );

  static final punchHistory = StaffEntry(
    moduleCode: 'MobileAttendance',
    title: 'Lịch sử chấm công',
    icon: Icons.history,
    color: SboxColors.primary,
    ownScaffold: true,
    builder: (_) => const MobileAttendanceHistoryScreen(),
  );

  static final correction = StaffEntry(
    moduleCode: 'AttendanceCorrection',
    title: 'Giải trình / bổ sung công',
    icon: Icons.edit_calendar_outlined,
    color: SboxColors.warning,
    builder: (_) => const AttendanceCorrectionsScreen(),
  );

  /// Gửi thông tin máy để quản lý duyệt — chưa duyệt thì nút chấm công bị khóa.
  static final device = StaffEntry(
    moduleCode: 'MobileDeviceRegistration',
    title: 'Đăng ký thiết bị chấm công',
    subtitle: 'Gửi máy này để quản lý duyệt',
    icon: Icons.phonelink_setup_outlined,
    color: SboxColors.primary,
    ownScaffold: true,
    builder: (_) => const MobileDeviceRegistrationScreen(),
  );

  static final shiftSwap = StaffEntry(
    moduleCode: 'ShiftSwap',
    title: 'Đổi ca',
    subtitle: 'Nhờ đồng nghiệp làm thay / đổi ca',
    icon: Icons.swap_horiz,
    color: SboxColors.primary,
    builder: (_) => const ShiftSwapScreen(),
  );

  static final payslip = StaffEntry(
    moduleCode: 'Payslip',
    title: 'Phiếu lương',
    icon: Icons.receipt_long_outlined,
    color: SboxColors.success,
    builder: (_) => const PayslipScreen(),
  );

  static final rewards = StaffEntry(
    moduleCode: 'BonusPenalty',
    title: 'Thưởng / phạt',
    icon: Icons.emoji_events_outlined,
    color: SboxColors.warning,
    builder: (_) => const HrFinanceHubScreen(initialTab: HrFinTab.rewards),
  );

  static final penalty = StaffEntry(
    moduleCode: 'PenaltyTickets',
    title: 'Phiếu phạt',
    icon: Icons.receipt_outlined,
    color: SboxColors.danger,
    builder: (_) => const HrFinanceHubScreen(
        initialTab: HrFinTab.rewards, initialRewardKind: 'penalty'),
  );

  static final advance = StaffEntry(
    moduleCode: 'AdvanceRequests',
    title: 'Tạm ứng lương',
    icon: Icons.payments_outlined,
    color: SboxColors.success,
    builder: (_) => const AdvanceRequestsScreen(),
  );

  static final leave = StaffEntry(
    moduleCode: 'Leave',
    title: 'Xin nghỉ phép',
    icon: Icons.beach_access_outlined,
    color: SboxColors.primary,
    builder: (_) => const LeaveScreen(),
  );

  static final overtime = StaffEntry(
    moduleCode: 'Overtime',
    title: 'Đăng ký tăng ca',
    icon: Icons.more_time,
    color: SboxColors.warning,
    builder: (_) => const OvertimeScreen(),
  );

  static final businessTrip = StaffEntry(
    moduleCode: 'BusinessTripExpense',
    title: 'Công tác phí',
    icon: Icons.luggage_outlined,
    color: SboxColors.primary,
    builder: (_) => const BusinessTripExpenseScreen(),
  );

  static final task = StaffEntry(
    moduleCode: 'Task',
    title: 'Công việc',
    icon: Icons.task_alt,
    color: SboxColors.primary,
    builder: (_) => const WorkHubScreen(),
  );

  static final news = StaffEntry(
    moduleCode: 'Communication',
    title: 'Bản tin nội bộ',
    subtitle: 'Thông báo, bài đăng của cửa hàng',
    icon: Icons.campaign_outlined,
    color: SboxColors.primary,
    builder: (_) => DeferredScreen(
      load: comm_hub.loadLibrary,
      builder: () => comm_hub.CommHubScreen(),
    ),
  );

  static final meal = StaffEntry(
    moduleCode: 'Meal',
    title: 'Suất ăn',
    icon: Icons.restaurant_outlined,
    color: SboxColors.warning,
    builder: (_) => const MealTrackingScreen(),
  );

  static final feedback = StaffEntry(
    moduleCode: 'Feedback',
    title: 'Góp ý',
    icon: Icons.feedback_outlined,
    color: SboxColors.textSecondary,
    builder: (_) => const FeedbackScreen(),
  );

  /// Ô thao tác nhanh ở Trang chủ.
  static List<StaffEntry> get quickActions =>
      [leave, overtime, correction, payslip, advance, task];

  static List<StaffEntry> get attendanceAndPay =>
      [punch, punchHistory, correction, device];

  /// «Thưởng / phạt» đã gồm phiếu phạt — chỉ hiện «Phiếu phạt» riêng khi vai trò không xem được thưởng.
  static List<StaffEntry> pay(bool canSeeRewards) =>
      [payslip, if (canSeeRewards) rewards else penalty, advance];

  static List<StaffEntry> get requests =>
      [leave, overtime, shiftSwap, businessTrip];

  static List<StaffEntry> get work => [news, task, meal, feedback];
}
