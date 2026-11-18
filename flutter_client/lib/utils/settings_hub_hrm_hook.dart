import 'package:flutter/widgets.dart';

/// Trang thiết lập chỉ có ở SBOX HRM (ca làm việc, chấm công di động, phụ cấp, bảo hiểm, thuế, lương
/// theo sản phẩm, định biên, thiết bị chấm công, nghỉ phép năm).
///
/// `lib/main.dart` (bản HRM) gán hàm này lúc khởi động; bản SBOX Bán Hàng **không gán**, nên trình biên dịch
/// không đưa các màn đó vào gói. Apple từ chối bản POS theo điều 2.5.19 vì quét thấy mã chấm công / lương
/// nằm trong gói dù giao diện đã ẩn.
Widget? Function(int index)? settingsHubHrmPage;
