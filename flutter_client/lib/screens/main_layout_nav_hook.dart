import 'main_layout.dart' show NavItem;

/// Mục điều hướng của SBOX HRM, gắn từ `lib/main.dart`.
///
/// Bản SBOX Bán Hàng (`lib/main_pos.dart`) không gắn, nên 37 mục chấm công / nghỉ phép / lương / nhân sự
/// cùng toàn bộ màn hình chúng dựng không nằm trong gói — Apple từ chối bản POS theo điều 2.5.19 vì
/// quét thấy chính nhóm mã này.
Map<String, NavItem>? hrmNavItemsHook;
