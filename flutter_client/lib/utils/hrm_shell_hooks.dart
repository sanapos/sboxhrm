import 'package:flutter/widgets.dart';

import '../services/api_service.dart';

/// Các mảnh chỉ của SBOX HRM mà khung màn chung (`main_layout`) gọi tới.
///
/// `lib/main.dart` gắn đủ; `lib/main_pos.dart` (SBOX Bán Hàng) **không gắn gì**, nên trình biên dịch Dart
/// không đưa màn tăng ca, sổ nhân sự — tài chính và panel đồng bộ máy chấm công vào gói iOS.
/// Apple từ chối bản POS theo điều 2.5.19 vì quét thấy đúng nhóm mã này trong gói.

/// Màn «Quản lý tăng ca» — null ở bản bán hàng, menu cũng không có mục này.
Widget Function()? hrmOvertimePage;

/// Sổ nhân sự — tài chính (ứng lương, thưởng phạt, công tác phí). Bản bán hàng chỉ có sổ thu chi cửa hàng.
Widget Function()? hrmCashHubScreen;

/// Panel tiến trình đồng bộ máy chấm công, bọc ngoài khung màn. Bản bán hàng trả lại chính `child`.
Widget Function(Widget child)? hrmShellOverlay;

/// Đang đồng bộ máy chấm công thì không nảy popup cho từng lượt quét (dồn hàng trăm cái).
bool Function(DateTime punchTime)? hrmSuppressPunchPopup;

/// Đang đồng bộ thì bỏ qua cả thông báo chấm công / thiết bị.
bool Function()? hrmSuppressPunchNotifications;

/// Một loạt lượt quét trên máy chấm công → làm mới bảng công, bảng lương (gom 2 giây một lần).
void Function()? hrmOnPunchRefresh;

/// Thiết bị chấm công mobile được duyệt / đổi máy → làm mới hai màn thiết lập tương ứng.
void Function()? hrmOnMobileDeviceRefresh;

/// Tổng quan mở bảng «nhân viên theo trạng thái chuyên cần» — chỉ có ở bản HRM.
void Function(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Map<String, dynamic>> rows,
  VoidCallback? onTapRow,
})? hrmOverviewPeopleSheet;

/// Tổng quan mở bảng «đi trễ hôm nay + phiếu phạt» — chỉ có ở bản HRM.
Future<void> Function(
  BuildContext context, {
  required List<Map<String, dynamic>> lateRows,
  required bool canApprove,
  required ApiService api,
  VoidCallback? onOpenPenalties,
})? hrmLatePenaltySheet;
