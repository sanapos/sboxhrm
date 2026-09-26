/// Loại gói theo chức năng người dùng THỰC SỰ dùng được (gói + phân quyền):
/// chỉ chấm công / chỉ bán hàng / đầy đủ. Quyết định bộ công cụ chính trên thanh dưới + lối tắt.
enum NavPackageKind { full, attendance, pos }

abstract final class NavPackageProfile {
  /// [allowedIds] = mã chức năng người dùng vào được (đã lọc gói + quyền).
  static NavPackageKind detect(Set<String> allowedIds) {
    final pos = allowedIds.contains('PosSell') ||
        allowedIds.contains('PosSaleOrders') ||
        allowedIds.contains('PosProducts');
    final att = allowedIds.contains('MobileAttendance') ||
        allowedIds.contains('Attendance') ||
        allowedIds.contains('Leave') ||
        allowedIds.contains('Payslip');
    if (pos && !att) return NavPackageKind.pos;
    if (att && !pos) return NavPackageKind.attendance;
    return NavPackageKind.full;
  }

  /// Thanh dưới mặc định (5 ô, ô giữa là thao tác chính, ô cuối «Thêm»).
  static List<String> defaultMainSlots(NavPackageKind kind) => switch (kind) {
        NavPackageKind.attendance => const ['Home', 'Leave', 'MobileAttendance', 'Payslip', '_drawer'],
        NavPackageKind.pos => const ['Home', 'PosProducts', 'PosSell', 'PosSaleOrders', '_drawer'],
        NavPackageKind.full => const ['Home', 'PosSell', 'MobileAttendance', 'SettingsHub', '_drawer'],
      };

  /// Thứ tự ưu tiên để lấp ô bị mất quyền (không để ô trống).
  static List<String> mainPriority(NavPackageKind kind) => switch (kind) {
        NavPackageKind.attendance => const [
            'Home', 'MobileAttendance', 'Leave', 'Payslip', 'Task', 'Notification',
            'Employee', 'Payroll', 'Communication', 'Dashboard', 'SettingsHub',
          ],
        NavPackageKind.pos => const [
            'Home', 'PosSell', 'PosSaleOrders', 'PosProducts', 'PosSalesReport', 'PosKds',
            'Notification', 'SettingsHub', 'Dashboard',
          ],
        NavPackageKind.full => const [
            'Home', 'PosSell', 'MobileAttendance', 'PosSaleOrders', 'PosProducts', 'Task', 'Leave',
            'Payslip', 'Notification', 'SettingsHub', 'Dashboard', 'PosSalesReport', 'Employee',
            'Payroll', 'Communication', 'PosKds',
          ],
      };

  /// Lối tắt nhanh mặc định trong ngăn «Thêm» (9 ô).
  static List<String> defaultQuickActions(NavPackageKind kind) => switch (kind) {
        NavPackageKind.attendance => const [
            'Attendance', 'Leave', 'Payslip', 'Task', 'AdvanceRequests',
            'FieldCheckIn', 'Communication', 'Notification', 'Employee',
          ],
        NavPackageKind.pos => const [
            'PosSell', 'PosSaleOrders', 'PosProducts', 'PosSalesReport', 'PosSaleReturns',
            'PosPurchaseReceipts', 'PosStockCounts', 'PosKds', 'SettingsHub',
          ],
        NavPackageKind.full => const [
            'PosSell', 'PosQuotes', 'PosPrintTemplates', 'PosProducts', 'PosSaleOrders',
            'PosKds', 'PosSalesReport', 'SettingsHub', 'Employee',
          ],
      };

  static String label(NavPackageKind kind) => switch (kind) {
        NavPackageKind.attendance => 'Gói chấm công',
        NavPackageKind.pos => 'Gói bán hàng (POS)',
        NavPackageKind.full => 'Gói đầy đủ',
      };
}
