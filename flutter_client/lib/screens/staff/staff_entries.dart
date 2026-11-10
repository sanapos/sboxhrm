import 'package:flutter/material.dart';

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
import '../shift_hub/shift_hub_screen.dart';
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
    icon: Icons.fingerprint_rounded,
    builder: (_) => const MobileAttendanceScreen(),
  );

  static final punchHistory = StaffEntry(
    moduleCode: 'MobileAttendance',
    title: 'Lịch sử chấm công',
    icon: Icons.history_rounded,
    ownScaffold: true,
    builder: (_) => const MobileAttendanceHistoryScreen(),
  );

  static final correction = StaffEntry(
    moduleCode: 'AttendanceCorrection',
    title: 'Sửa chấm công',
    icon: Icons.edit_calendar_rounded,
    ownScaffold: true,
    builder: (_) => const AttendanceCorrectionsScreen(),
  );

  /// Gửi thông tin máy để quản lý duyệt — chưa duyệt thì nút chấm công bị khóa.
  static final device = StaffEntry(
    moduleCode: 'MobileDeviceRegistration',
    title: 'Đăng ký chấm công Mobile',
    subtitle: 'Gửi máy này để quản lý duyệt',
    icon: Icons.phonelink_setup_rounded,
    ownScaffold: true,
    builder: (_) => const MobileDeviceRegistrationScreen(),
  );

  static final shiftSwap = StaffEntry(
    moduleCode: 'ShiftSwap',
    title: 'Đổi ca',
    subtitle: 'Nhờ đồng nghiệp làm thay / đổi ca',
    icon: Icons.swap_horiz_rounded,
    // Một cửa: Lịch của tôi + bảng đổi ca của Ca làm việc (thiếu quyền Ca làm việc dùng màn cũ).
    builder: (_) => const MyScheduleEntry(action: 'swap', fallback: ShiftSwapScreen()),
  );

  static final payslip = StaffEntry(
    moduleCode: 'Payslip',
    title: 'Phiếu lương',
    icon: Icons.receipt_long_rounded,
    builder: (_) => const PayslipScreen(),
  );

  static final rewards = StaffEntry(
    moduleCode: 'BonusPenalty',
    title: 'Thưởng / phạt',
    icon: Icons.emoji_events_rounded,
    builder: (_) => const HrFinanceHubScreen(initialTab: HrFinTab.rewards),
  );

  static final penalty = StaffEntry(
    moduleCode: 'PenaltyTickets',
    title: 'Phiếu phạt',
    icon: Icons.receipt_rounded,
    builder: (_) => const HrFinanceHubScreen(
        initialTab: HrFinTab.rewards, initialRewardKind: 'penalty'),
  );

  static final advance = StaffEntry(
    moduleCode: 'AdvanceRequests',
    title: 'Tạm ứng lương',
    icon: Icons.payments_rounded,
    builder: (_) => const AdvanceRequestsScreen(),
  );

  static final leave = StaffEntry(
    moduleCode: 'Leave',
    title: 'Xin nghỉ phép',
    icon: Icons.beach_access_rounded,
    builder: (_) => const MyScheduleEntry(action: 'leave', fallback: LeaveScreen()),
  );

  static final overtime = StaffEntry(
    moduleCode: 'Overtime',
    title: 'Đăng ký tăng ca',
    icon: Icons.more_time_rounded,
    builder: (_) => const OvertimeScreen(),
  );

  static final businessTrip = StaffEntry(
    moduleCode: 'BusinessTripExpense',
    title: 'Công tác phí',
    icon: Icons.luggage_rounded,
    builder: (_) => const BusinessTripExpenseScreen(),
  );

  static final task = StaffEntry(
    moduleCode: 'Task',
    title: 'Công việc',
    icon: Icons.task_alt_rounded,
    builder: (_) => const WorkHubScreen(),
  );

  static final news = StaffEntry(
    moduleCode: 'Communication',
    title: 'Bản tin nội bộ',
    subtitle: 'Thông báo, bài đăng của cửa hàng',
    icon: Icons.campaign_rounded,
    builder: (_) => DeferredScreen(
      load: comm_hub.loadLibrary,
      builder: () => comm_hub.CommHubScreen(),
    ),
  );

  static final meal = StaffEntry(
    moduleCode: 'Meal',
    title: 'Suất ăn',
    icon: Icons.restaurant_rounded,
    builder: (_) => const MealTrackingScreen(),
  );

  static final feedback = StaffEntry(
    moduleCode: 'Feedback',
    title: 'Góp ý',
    icon: Icons.feedback_rounded,
    builder: (_) => const FeedbackScreen(),
  );

  /// Màn mở khi bấm thông báo, theo loại thông báo đã chuẩn hóa (không gồm Lịch: Lịch là tab của khung).
  static StaffEntry? forNotification(String? entityKey) => switch (entityKey) {
        'attendance' || 'newattendance' || 'mobileattendance' => punchHistory,
        'authorizedmobiledevice' || 'devicechangerequest' || 'mobiledeviceregistration' => device,
        'attendancecorrection' || 'correction' => correction,
        'overtime' => overtime,
        'leave' || 'leaverequest' => leave,
        'advancerequest' || 'advance' => advance,
        'businesstripcase' || 'businesstripexpense' => businessTrip,
        'payslip' || 'payroll' => payslip,
        'shiftswap' => shiftSwap,
        'worktask' || 'task' => task,
        'communication' => news,
        'penaltyticket' || 'penaltytickets' => penalty,
        'bonuspenalty' || 'benefit' || 'paymenttransaction' => rewards,
        'mealrecord' || 'mealsession' || 'mealmenu' => meal,
        'feedback' => feedback,
        _ => null,
      };

  /// Loại thông báo về lịch làm việc: mở tab Lịch.
  static bool isScheduleNotification(String? entityKey) => const {
        'scheduleregistration',
        'workschedule',
        'shift',
        'schedule',
      }.contains(entityKey);

  /// Ô thao tác nhanh ở Trang chủ.
  static List<StaffEntry> get quickActions =>
      [leave, overtime, correction, shiftSwap, payslip, advance, task, news];

  static List<StaffEntry> get attendanceAndPay =>
      [punch, punchHistory, correction, device];

  /// «Thưởng / phạt» đã gồm phiếu phạt — chỉ hiện «Phiếu phạt» riêng khi vai trò không xem được thưởng.
  static List<StaffEntry> pay(bool canSeeRewards) =>
      [payslip, if (canSeeRewards) rewards else penalty, advance];

  static List<StaffEntry> get requests =>
      [leave, overtime, shiftSwap, businessTrip];

  static List<StaffEntry> get work => [news, task, meal, feedback];
}
