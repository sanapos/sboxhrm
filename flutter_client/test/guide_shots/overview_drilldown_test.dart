import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/features/boss/boss_dashboard_screen.dart';
import 'package:zkteco_flutter_client/features/boss/boss_shell.dart';
import 'package:zkteco_flutter_client/screens/overview/business_overview_screen.dart';

import 'guide_shot_kit.dart';

// Tổng quan cho chủ quán: mọi con số bấm ra chi tiết (BOSS «Tổng quan hôm nay», HRM/POS «Tổng quan»).
// Chạy kèm ảnh: GUIDE_SHOT_DIR=… GUIDE_SHOT_PLAIN=1 flutter test test/guide_shots/overview_drilldown_test.dart

final _now = DateTime.now();
String _day(int back) {
  final d = DateTime(_now.year, _now.month, _now.day).subtract(Duration(days: back));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final _bossDashboard = {
  'storeName': 'Quán Cơm Gà Nam',
  'businessDate': _day(0),
  'dayStartHour': 0,
  'generatedAt': DateTime.now().toUtc().toIso8601String(),
  'today': {
    'revenue': 2450000, 'orderCount': 18, 'avgOrder': 136000, 'discount': 120000,
    'collected': 2100000, 'collectedCash': 900000, 'unpaid': 350000, 'unpaidCount': 2,
    'expense': 400000, 'expenseCash': 300000, 'expenseCount': 3, 'canceledCount': 2, 'canceledTotal': 180000,
    'cogs': 1350000, 'grossProfit': 1100000,
  },
  'yesterdaySameTime': {'revenue': 2000000, 'orderCount': 15},
  'yesterdayFull': {'revenue': 3100000, 'orderCount': 25},
  'lastWeekSameTime': {'revenue': 1800000, 'orderCount': 12},
  'byHour': [
    for (var h = 0; h < 24; h++)
      {'hour': h, 'today': h >= 7 && h <= 13 ? (h * 37 % 9 + 2) * 60000 : 0, 'yesterday': h >= 7 && h <= 21 ? (h * 13 % 7 + 2) * 55000 : 0},
  ],
  'byPayment': [
    {'method': 'Cash', 'label': 'Tiền mặt', 'total': 900000, 'count': 8},
    {'method': 'VietQR', 'label': 'VietQR', 'total': 1200000, 'count': 8},
  ],
  'openTables': {
    'count': 2,
    'amount': 650000,
    'items': [
      {'name': 'Bàn 5', 'area': 'Trong nhà', 'startedAt': '10:05', 'minutes': 205, 'amount': 420000, 'guests': 4, 'billRequested': true},
      {'name': 'Bàn 2', 'area': 'Sân vườn', 'startedAt': '12:40', 'minutes': 50, 'amount': 230000, 'guests': 2, 'billRequested': false},
    ],
  },
  'staff': {'active': 7, 'checkedIn': 5, 'late': 2, 'onLeave': 1},
};

final _bossOrders = {
  'count': 2,
  'total': 180000,
  'items': [
    {'id': '', 'orderNo': 'HD0012', 'time': '11:20', 'total': 120000, 'paid': 0, 'unpaid': 0, 'soldBy': 'Lan', 'paymentMethod': 'Tiền mặt'},
    {'id': '', 'orderNo': 'HD0009', 'time': '09:02', 'total': 60000, 'paid': 0, 'unpaid': 0, 'soldBy': 'Minh', 'paymentMethod': 'Tiền mặt'},
  ],
};

final _api = guideApi({
  '/api/pos/reports/boss/dashboard': _bossDashboard,
  '/api/pos/reports/boss/orders': _bossOrders,
  '/api/overview/todos': [],
  '/api/pos/reports/sales/summary': {
    'totalRevenue': 5000000, 'totalRevenueInclVat': 5000000, 'totalPaid': 4200000, 'totalProfit': 2000000,
    'orderCount': 30,
    'profitByDay': [for (var i = 6; i >= 0; i--) {'date': _day(i), 'revenue': 600000 + i * 50000, 'profit': 250000}],
    'byPayment': [{'paymentMethod': 'Tiền mặt', 'total': 2000000}, {'paymentMethod': 'VietQR', 'total': 2200000}],
    'topProducts': [{'productName': 'Cơm gà', 'revenue': 1800000, 'qty': 40}],
    'topEmployees': [{'soldBy': 'lan@quan.vn', 'displayName': 'Trần Thị Lan', 'orderCount': 18, 'revenue': 3000000}],
  },
  '/api/pos/reports/stock/summary': {'outOfStockCount': 3},
  '/api/Dashboard/manager': {},
  '/api/dashboard/attendance-trends': [
    for (var i = 6; i >= 1; i--)
      {'date': _day(i), 'present': 6, 'onTime': 5, 'late': 1, 'absent': 1, 'onLeave': 0, 'total': 7},
    {
      'date': _day(0), 'present': 5, 'onTime': 4, 'late': 1, 'absent': 1, 'onLeave': 1, 'total': 7,
      'employees': [
        {'fullName': 'Nguyễn Văn Hùng', 'department': 'Bếp', 'shiftStart': '07:00', 'shiftEnd': '15:00', 'checkIn': '06:55', 'status': 'Present', 'lateMinutes': 0},
        {'fullName': 'Trần Thị Lan', 'department': 'Phục vụ', 'shiftStart': '08:00', 'shiftEnd': '16:00', 'checkIn': '08:21', 'status': 'Late', 'lateMinutes': 21},
        {'fullName': 'Lê Văn Minh', 'department': 'Phục vụ', 'shiftStart': '08:00', 'shiftEnd': '16:00', 'status': 'Absent', 'lateMinutes': 0},
        {'fullName': 'Phạm Thị Hoa', 'department': 'Thu ngân', 'status': 'On Leave', 'lateMinutes': 0},
      ],
    },
  ],
});

void main() {
  testWidgets('overview-boss-0: lãi gộp, đi trễ / nghỉ phép; thanh dưới gọn như SBOX HRM', (t) async {
    await guideShot(t, name: 'overview-boss-0', screen: const BossShell(), api: _api, size: mobileSize,
        act: (t) async {
      expect(find.text('Lãi gộp'), findsOneWidget);
      // Thanh dưới: trước NavigationBar Material 3 cao 80.
      final bar = t.getSize(find.ancestor(of: find.text('Cần duyệt').last, matching: find.byType(Material)).first);
      expect(bar.height, lessThanOrEqualTo(60));
      await guideScrollTo(t, find.text('Đã chấm công'), alignment: 0.5);
      expect(find.text('Trễ 2 · Nghỉ phép 1'), findsOneWidget);
    });
    // Khung BOSS còn hẹn giờ quyền (12 giây) và nối lại SignalR — chạy hết sau khi gỡ cây.
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('overview-boss-1: tiền hôm nay, chưa thu, bàn đang mở bấm ra danh sách', (t) async {
    await guideShot(t, name: 'overview-boss-1', screen: const BossDashboardScreen(), api: _api, size: mobileSize,
        act: (t) async {
      expect(find.text('Chưa thu'), findsOneWidget);
      expect(find.text('Tiền hôm nay'), findsOneWidget);
      expect(find.text('Cần để mắt hôm nay'), findsOneWidget);
      expect(find.textContaining('tuần trước, tới'), findsOneWidget);
      await guideScrollTo(t, find.text('Bàn đang mở'), alignment: 0.4);
      await t.tap(find.text('Bàn đang mở'));
      await t.pumpAndSettle();
      expect(find.text('Bàn đang mở (2)'), findsOneWidget);
      expect(find.text('Bàn 5'), findsOneWidget);
      expect(find.text('Đã gọi tính tiền'), findsOneWidget);
    });
  });

  testWidgets('overview-boss-2: đơn hủy hôm nay', (t) async {
    await guideShot(t, name: 'overview-boss-2', screen: const BossDashboardScreen(), api: _api, size: mobileSize,
        act: (t) async {
      await t.tap(find.text('Đơn hủy'));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Đơn hủy hôm nay'), findsOneWidget);
      expect(find.text('HD0012'), findsOneWidget);
    });
  });

  testWidgets('overview-boss-3: giải thích các số', (t) async {
    await guideShot(t, name: 'overview-boss-3', screen: const BossDashboardScreen(), api: _api, size: mobileSize,
        act: (t) async {
      await t.tap(find.byIcon(Icons.help_outline_rounded));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.textContaining('Bàn đang mở'), findsWidgets);
      expect(find.text('Chưa thu'), findsWidgets);
    });
  });

  testWidgets('overview-hrm-1: tách kỳ bán hàng / nhân sự hôm nay, chưa thu', (t) async {
    await guideShot(t, name: 'overview-hrm-1',
        screen: const BusinessOverviewScreen(mode: OverviewMode.combined, canAccess: _all), api: _api, size: mobileSize,
        act: (t) async {
      expect(find.textContaining('Bán hàng ·'), findsOneWidget);
      expect(find.text('Nhân sự · hôm nay'), findsOneWidget);
      expect(find.text('Chưa thu (khách nợ)'), findsOneWidget);
      expect(find.text('Lãi gộp (chưa trừ chi phí)'), findsOneWidget);
    });
  });

  testWidgets('overview-hrm-2: ô «Đi trễ hôm nay» bấm ra danh sách người', (t) async {
    await guideShot(t, name: 'overview-hrm-2',
        screen: const BusinessOverviewScreen(mode: OverviewMode.combined, canAccess: _all), api: _api, size: mobileSize,
        act: (t) async {
      await guideScrollTo(t, find.text('Đi trễ hôm nay'), alignment: 0.4);
      await t.tap(find.text('Đi trễ hôm nay'));
      await t.pumpAndSettle();
      expect(find.text('Đi trễ hôm nay (1)'), findsOneWidget);
      expect(find.text('Trần Thị Lan'), findsWidgets);
      expect(find.text('Trễ 21p'), findsOneWidget);
    });
  });
}

bool _all(String _) => true;
