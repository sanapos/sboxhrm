import 'package:flutter/widgets.dart';

import 'app/app_shells.dart';
import 'app_boot.dart';
import 'screens/main_layout.dart';

/// Điểm vào riêng của **SBOX Bán Hàng** (bản iOS).
///
/// Khác `lib/main.dart` ở đúng một điểm: KHÔNG gắn phần của SBOX HRM — khung `MainLayout`, các mục Thiết lập
/// chấm công / lương, cảm biến sinh trắc (`local_auth`) và báo vị trí (`geolocator`). Trình biên dịch Dart chỉ
/// đưa vào gói những gì với tới được từ điểm vào, nên mã đó không còn nằm trong bản bán hàng.
///
/// Apple từ chối bản POS ngày 17/11/2026 theo điều 2.5.19: máy quét đọc mã trong gói và kết luận app chứa
/// chấm công, sinh trắc, theo dõi vị trí và tính lương — ẩn giao diện không đủ, phải không biên dịch vào gói.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Khung màn giống hệt bản POS hiện tại; không gắn hrmNavItemsHook nên chỉ còn mục bán hàng.
  AppShells.hrm = () => const MainLayout();
  await runSbox();
}
