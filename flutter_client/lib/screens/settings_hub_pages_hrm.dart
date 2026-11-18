import 'package:flutter/material.dart';

import 'allowance_settings_screen.dart';
import 'annual_leave/al_policy.dart';
import 'device_management_settings_screen.dart';
import 'gateway/zk_gateway_list_screen.dart';
import 'holiday_settings_screen.dart';
import 'insurance_settings_screen.dart';
import 'mobile_attendance_settings_screen.dart';
import 'penalty_settings_screen.dart';
import 'product_salary_settings_screen.dart';
import 'shift_settings_screen.dart';
import 'staffing_quota_settings_screen.dart';
import 'store_access_devices_screen.dart';
import 'tax_settings_screen.dart';

/// Các mục Thiết lập SBOX chỉ có ở bản HRM. Mã mục giữ nguyên như bảng cũ trong `settings_hub_screen.dart`
/// (xem `SettingsHubCatalog`), nên thêm mục mới phải sửa cả hai nơi.
///
/// Tệp này chỉ được nạp từ `lib/main.dart`; bản SBOX Bán Hàng dùng điểm vào riêng và không gán hàm này,
/// nhờ vậy mã chấm công / lương / thiết bị chấm công không nằm trong gói (Apple 2.5.19).
Widget? hrmSettingsHubPage(int index) => switch (index) {
      0 => const ShiftSettingsScreen(),
      1 => const MobileAttendanceSettingsScreen(),
      2 => const HolidaySettingsScreen(),
      3 => const AllowanceSettingsScreen(),
      4 => const PenaltySettingsScreen(),
      5 => const InsuranceSettingsScreen(),
      6 => const TaxSettingsScreen(),
      10 => const ProductSalarySettingsScreen(),
      12 => const DeviceManagementSettingsScreen(),
      14 => const StaffingQuotaSettingsScreen(),
      25 => const ZkGatewayListScreen(),
      30 => const StoreAccessDevicesScreen(),
      31 => const AnnualLeavePolicyScreen(),
      _ => null,
    };
