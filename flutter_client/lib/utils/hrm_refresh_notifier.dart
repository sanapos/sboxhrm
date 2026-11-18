import 'dart:async';

import 'package:flutter/foundation.dart';

import 'screen_refresh_notifier.dart';

/// Kênh làm mới màn **chỉ của SBOX HRM**: chấm công, bảng công, bảng lương, thiết bị chấm công mobile.
///
/// Tách khỏi `ScreenRefreshNotifier` (dùng chung với POS) để bản SBOX Bán Hàng trên iOS không biên dịch
/// nhóm này vào gói — Apple 2.5.19. Khung màn chung gọi qua hook trong `hrm_shell_hooks.dart`.
abstract final class HrmRefresh {
  static final ValueNotifier<int> attendance = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceByShift = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceSummary = ValueNotifier<int>(0);
  static final ValueNotifier<int> payroll = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileAttendanceSettings = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileDeviceRegistration = ValueNotifier<int>(0);

  static void refreshAttendanceScreen() {
    attendance.value++;
  }

  static void refreshAttendanceByShiftScreen() {
    attendanceByShift.value++;
  }

  static void refreshAttendanceSummaryScreen() {
    attendanceSummary.value++;
  }

  static void refreshPayrollScreen() {
    payroll.value++;
  }

  static void refreshMobileAttendanceSettings() {
    mobileAttendanceSettings.value++;
  }

  static void refreshMobileDeviceRegistration() {
    mobileDeviceRegistration.value++;
  }

  static Timer? _dataRefreshTimer;

  /// Gom lượt quét — tối đa 1 lần / 2 giây thay vì mỗi lượt.
  static void scheduleDataRefresh() {
    _dataRefreshTimer?.cancel();
    _dataRefreshTimer = Timer(const Duration(seconds: 2), () {
      refreshAttendanceScreen();
      refreshAttendanceSummaryScreen();
      refreshAttendanceByShiftScreen();
      refreshPayrollScreen();
      ScreenRefreshNotifier.schedulePunchDashboardRefresh();
    });
  }
}
