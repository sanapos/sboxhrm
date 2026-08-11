/// Tên hiển thị module phân quyền — khớp menu app (main_layout, settings_hub).
class PermissionModuleLabels {
  PermissionModuleLabels._();

  static const Map<String, String> byModule = {
    // Tổng quan
    'Home': 'Trang chủ',
    'Notification': 'Thông báo',
    'Dashboard': 'Tổng quan (cũ)',
    'DashboardAttendanceOverview': 'Tổng quan chấm công',
    'DashboardHrInsights': 'Chỉ số nhân sự & vận hành',
    'DashboardTodaySchedule': 'Lịch làm việc hôm nay',
    'DashboardRealtimeAttendance': 'Chấm công thời gian thực',
    'DashboardAbsent': 'Nhân viên vắng mặt',
    'DashboardLateEarly': 'Đi trễ / về sớm',
    'DashboardKpiPanel': 'KPI (Dashboard)',
    'DashboardInternalNews': 'Bản tin nội bộ',
    // Hồ sơ nhân sự
    'Employee': 'Hồ sơ nhân sự',
    'DeviceUser': 'Nhân sự chấm công',
    'Department': 'Phòng ban',
    'Leave': 'Nghỉ phép',
    'SalarySettings': 'Thiết lập lương',
    'Payslip': 'Phiếu lương',
    'HrDocument': 'Tài liệu HR',
    'OrgChart': 'Sơ đồ tổ chức',
    // Chấm công
    'Attendance': 'Chấm công thô',
    'WorkSchedule': 'Lịch làm việc',
    'AttendanceSummary': 'Tổng hợp chấm công',
    'AttendanceByShift': 'Tổng hợp chấm công theo ca',
    'LateEarlyReport': 'Đi trễ / Về sớm',
    'TravelHoursReport': 'Báo cáo đi đường',
    'AttendanceCorrection': 'Chỉnh sửa chấm công',
    'AttendanceApproval': 'Duyệt chấm công',
    'MobileAttendanceApproval': 'Duyệt chấm công Mobile',
    'ScheduleApproval': 'Duyệt lịch làm việc',
    'Payroll': 'Tổng hợp lương',
    'Overtime': 'Tăng ca',
    'ShiftSwap': 'Đổi ca',
    'MobileDeviceRegistration': 'Đăng ký chấm công Mobile',
    'MobileAttendance': 'Chấm công Mobile',
    'Meal': 'Chấm cơm',
    'FieldCheckIn': 'Bản đồ nhân sự',
    'PosProducts': 'Hàng hóa POS',
    'PosSell': 'Bán hàng POS (Order / Thu ngân)',
    'PosPrintTemplates': 'Mẫu in POS',
    'PosSaleOrders': 'Đơn hàng POS',
    'PosSaleReturns': 'Trả hàng bán',
    'PosPurchaseReceipts': 'Nhập hàng NCC',
    'PosPurchaseReturns': 'Trả hàng nhập',
    'PosStockCounts': 'Kiểm kho POS',
    'PosDamageIssues': 'Xuất hủy POS',
    'PosInternalUseIssues': 'Xuất dùng nội bộ',
    'PosSalesReport': 'Báo cáo doanh thu POS',
    'HkdBooks': 'Sổ sách HKD',
    'PosBooking': 'Đặt bàn / lịch hẹn',
    'PosCustomers': 'Khách hàng POS',
    'PosWarranty': 'Bảo hành POS',
    'PosCustomerDisplay': 'Màn hình phụ POS',
    // Tài chính
    'BonusPenalty': 'Phiếu thưởng',
    'PenaltyTickets': 'Phiếu phạt',
    'AdvanceRequests': 'Ứng lương',
    'BusinessTripExpense': 'Công tác phí',
    'CashTransaction': 'Thu chi',
    'BankAccount': 'Tài khoản ngân hàng',
    // Vận hành
    'Asset': 'Tài sản',
    'Task': 'Công việc',
    'Communication': 'Truyền thông',
    'KPI': 'KPI',
    'Production': 'Sản lượng',
    'Feedback': 'Phản ánh / Ý kiến',
    // Báo cáo
    'AttendanceReport': 'Báo cáo chấm công',
    'LeaveReport': 'Báo cáo nghỉ phép',
    'CashReport': 'Báo cáo thu chi',
    'PenaltyReport': 'Báo cáo phạt',
    'AdvanceReport': 'Báo cáo ứng lương',
    'BusinessTripReport': 'Báo cáo công tác phí',
    'AssetReport': 'Báo cáo tài sản',
    // Thiết lập HRM
    'SettingsHub': 'Thiết lập HRM',
    'ShiftSetup': 'Thiết lập ca',
    'Holiday': 'Ngày lễ',
    'Device': 'Máy chấm công',
    'Allowance': 'Phụ cấp',
    'PenaltySetup': 'Phạt',
    'Insurance': 'Bảo hiểm',
    'Tax': 'Thuế TNCN',
    'ProductSalary': 'Lương sản phẩm',
    'Branch': 'Chi nhánh',
    'Geofence': 'Vùng chấm công',
    'UserManagement': 'Tài khoản',
    'Role': 'Phân quyền',
    'DepartmentPermission': 'PQ Phòng ban',
    'SystemSettings': 'Hệ thống',
    'NotificationSettings': 'Thiết lập thông báo',
    'AIGemini': 'Thiết lập AI',
    'Settings': 'Cài đặt',
    // Legacy / API aliases (ẩn UI)
    'Shift': 'Ca làm việc (API)',
    'ShiftTemplate': 'Mẫu ca (API)',
    'ShiftSalaryLevel': 'Bậc lương ca (API)',
    'Benefit': 'Phúc lợi (API)',
    'Transaction': 'Giao dịch (API)',
    'Report': 'Báo cáo (cũ)',
    'GoogleDrive': 'Google Drive',
  };

  static String? forModule(String? module) {
    if (module == null || module.isEmpty) return null;
    return byModule[module];
  }

  static String resolve(String? module, [String? fallback]) {
    return forModule(module) ?? fallback ?? module ?? '';
  }
}
