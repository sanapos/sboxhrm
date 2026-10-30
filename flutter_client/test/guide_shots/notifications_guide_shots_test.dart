import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/notification_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/notifications_screen.dart';
import 'package:zkteco_flutter_client/services/signalr_service.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Thông báo & nhắc việc» (id: notifications).

Map<String, Object?> _pref(String code, String name, String desc, int order, [bool on = true]) =>
    {'categoryCode': code, 'categoryDisplayName': name, 'categoryDescription': desc, 'displayOrder': order, 'isEnabled': on};

final _prefs = [
  _pref('attendance', 'Chấm công', 'Nhắc quên chấm, chấm muộn, chấm bù', 1),
  _pref('mobile_attendance', 'Chấm công mobile', 'Yêu cầu chấm công từ điện thoại cần duyệt', 2),
  _pref('shift', 'Ca làm việc', 'Xếp ca, đổi ca, đăng ký ca', 3),
  _pref('device', 'Máy chấm công', 'Máy mất kết nối / kết nối lại', 4, false),
  _pref('leave', 'Nghỉ phép', 'Đơn nghỉ mới, kết quả duyệt', 5),
  _pref('overtime', 'Tăng ca', 'Đăng ký tăng ca, kết quả duyệt', 6),
  _pref('approval', 'Phê duyệt', 'Yêu cầu đang chờ bạn duyệt', 7),
  _pref('payroll', 'Phiếu lương', 'Phiếu lương tháng đã sẵn sàng', 8),
  _pref('penalty', 'Phiếu phạt', 'Phiếu phạt đi trễ / về sớm', 9),
  _pref('task', 'Công việc', 'Được giao việc, sắp đến hạn', 10),
  _pref('internal_comm', 'Bản tin nội bộ', 'Bài viết mới, bài bắt buộc đọc', 11),
  _pref('pos', 'Bán hàng', 'Đơn QR mới, tồn kho thấp', 12, false),
];

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, Object?> _n(String id, String code, String label, String title, String msg, Duration ago,
        {bool read = false, String? from}) =>
    {
      'id': id, 'type': 0, 'isRead': read, 'categoryCode': code, 'categoryLabel': label,
      'title': title, 'message': msg, 'fromUserName': from, 'createdAt': _ago(ago),
    };

final _items = [
  _n('n1', 'leave', 'Nghỉ phép', 'Đơn nghỉ phép chờ duyệt', 'Võ Minh Tuấn xin nghỉ phép năm ngày 31/10 (Ca chiều)',
      const Duration(minutes: 12), from: 'Võ Minh Tuấn'),
  _n('n2', 'shift', 'Ca làm việc', 'Yêu cầu đổi ca', 'Đặng Ngọc Lan muốn đổi Ca chiều 29/10 với Phạm Thu Hà — đồng nghiệp đã đồng ý',
      const Duration(minutes: 40), from: 'Đặng Ngọc Lan'),
  _n('n3', 'attendance', 'Chấm công', 'Quên chấm ra', 'Lê Văn Hùng chưa chấm ra ca chiều hôm qua',
      const Duration(hours: 9)),
  _n('n4', 'payroll', 'Phiếu lương', 'Phiếu lương tháng 9 đã sẵn sàng', 'Bạn có thể xem phiếu lương tháng 9/2026 trong mục Phiếu lương',
      const Duration(days: 2), read: true),
  _n('n5', 'internal_comm', 'Bản tin nội bộ', 'Bài bắt buộc đọc mới', 'Quy định chấm công và nghỉ phép 2026 (bản 3)',
      const Duration(days: 3), read: true, from: 'Phòng Nhân sự'),
];

final _api = guideApi({
  '/api/notification-preferences': _prefs,
  '/api/notifications/summary': {'unreadCount': 3, 'totalCount': 5},
  '/api/notifications/category-counts': [
    {'code': 'leave', 'total': 1, 'unread': 1},
    {'code': 'shift', 'total': 1, 'unread': 1},
    {'code': 'attendance', 'total': 1, 'unread': 1},
    {'code': 'payroll', 'total': 1, 'unread': 0},
    {'code': 'internal_comm', 'total': 1, 'unread': 0},
  ],
  '/api/notifications': {'items': _items, 'totalCount': _items.length},
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('notifications-1$suffix: chọn loại thông báo muốn nhận', (t) async {
      await guideShot(
        t,
        name: 'notifications-1$suffix',
        screen: const NotificationSettingsScreen(showPushCard: false),
        api: _api,
        crumbs: const ['Cài đặt', 'Thông báo'],
        size: size,
        act: (t) async => extrasSettle(t),
        marks: [
          GuideMark(1, [find.text('Chấm công & ca'), find.byType(Switch).first], pad: 8),
          GuideMark(2, [find.text('Máy chấm công').last, find.byType(Switch).at(4)], pad: 8),
        ],
      );
    });

    testWidgets('notifications-2$suffix: chuông thông báo, việc chờ xử lý', (t) async {
      await guideShot(
        t,
        name: 'notifications-2$suffix',
        screen: const NotificationsScreen(),
        api: _api,
        crumbs: const ['Thông báo'],
        size: size,
        act: (t) async => extrasSettle(t),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tất cả').first), GuideMark.button(find.text('Đã đọc').first)], pad: 4),
          GuideMark(2, [cardOf(find.text('Đơn nghỉ phép chờ duyệt').first)], pad: 4),
        ],
      );
      // Màn thông báo mở SignalR; trong test không có máy chủ → nó hẹn giờ kết nối lại. Dừng và cho hẹn giờ chạy hết.
      await SignalRService().disconnect();
      await t.pump(const Duration(seconds: 70));
    });
  }
}
