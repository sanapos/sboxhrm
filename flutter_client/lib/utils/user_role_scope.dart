/// Vai trò tự phục vụ (chỉ dữ liệu của mình) — khớp API IsEmployee: nhân viên, thu ngân, phục vụ, người dùng.
///
/// Để riêng một tệp vì `report_access_utils` (sổ thu chi của bản bán hàng) chỉ cần đúng hàm này, không cần
/// kéo theo `salary_profile_load_utils` — nhóm mã nạp hồ sơ lương. Apple 2.5.19: bản SBOX Bán Hàng không
/// được có mã tính lương trong gói.
bool isEmployeeUserRole(String? role) {
  final r = role?.trim().toLowerCase();
  return r == 'employee' || r == 'cashier' || r == 'waiter' || r == 'user';
}
