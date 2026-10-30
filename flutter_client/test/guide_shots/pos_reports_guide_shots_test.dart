import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_split_report_screens.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';
import 'package:zkteco_flutter_client/widgets/export_file_icon.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Cách xem báo cáo POS» (id: pos_reports).

String _day(int back) {
  final d = DateTime.now().subtract(Duration(days: back));
  return DateTime(d.year, d.month, d.day).toIso8601String();
}

final _byDayRevenue = [4850000, 5320000, 6120000, 3980000, 7450000, 8210000, 5640000];

final _summary = {
  'storeName': 'Cà phê Mộc',
  'totalRevenue': 41570000,
  'totalVat': 0,
  'totalRevenueInclVat': 41570000,
  'orderCount': 612,
  'totalPaid': 41250000,
  'totalRefund': 320000,
  'totalDiscount': 1180000,
  'byDay': [
    for (var i = 0; i < 7; i++) {'date': _day(6 - i), 'revenue': _byDayRevenue[i], 'orderCount': 70 + i * 9},
  ],
  'byPayment': [
    {'paymentMethod': 'Tiền mặt', 'total': 18650000, 'count': 301},
    {'paymentMethod': 'Chuyển khoản', 'total': 15420000, 'count': 214},
    {'paymentMethod': 'VietQR', 'total': 7180000, 'count': 97},
  ],
  'topEmployees': [
    {'soldBy': 'u2', 'displayName': 'Trần Thị Lan', 'orderCount': 248, 'revenue': 17240000},
    {'soldBy': 'u3', 'displayName': 'Lê Minh Quân', 'orderCount': 201, 'revenue': 13580000},
    {'soldBy': 'u4', 'displayName': 'Phạm Thu Hà', 'orderCount': 163, 'revenue': 10750000},
  ],
};

final _orders = {
  'total': 3,
  'items': [
    {'id': 'o1', 'code': 'HD000612', 'saleDate': _day(0), 'customerName': 'Khách lẻ', 'total': 89000, 'paidAmount': 89000, 'paymentMethod': 'Tiền mặt', 'soldByName': 'Trần Thị Lan'},
    {'id': 'o2', 'code': 'HD000611', 'saleDate': _day(0), 'customerName': 'Nguyễn Hoàng Nam', 'total': 145000, 'paidAmount': 145000, 'paymentMethod': 'VietQR', 'soldByName': 'Lê Minh Quân'},
    {'id': 'o3', 'code': 'HD000610', 'saleDate': _day(0), 'customerName': 'Khách lẻ', 'total': 55000, 'paidAmount': 55000, 'paymentMethod': 'Chuyển khoản', 'soldByName': 'Trần Thị Lan'},
  ],
};

/// Kỳ trước (tuần trước) thấp hơn để thẻ KPI hiện % tăng trưởng.
final _prevSummary = {
  ..._summary,
  'totalRevenue': 36820000,
  'totalRevenueInclVat': 36820000,
  'orderCount': 548,
  'totalPaid': 36500000,
  'totalRefund': 410000,
};

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/reports/sales/summary')) {
    final from = DateTime.tryParse(req.url.queryParameters['from'] ?? '');
    final isPrev = from != null && from.isBefore(DateTime.now().subtract(const Duration(days: 7)));
    return isPrev ? _prevSummary : _summary;
  }
  if (p.endsWith('/api/pos/reports/sales/orders')) return _orders;
  return null;
});

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('pos-reports-1$suffix: danh mục báo cáo POS', (t) async {
      await guideShot(
        t,
        name: 'pos-reports-1$suffix',
        screen: withPosPackage(const PosReportsHubScreen()),
        api: _api,
        crumbs: const ['Báo cáo', 'Báo cáo POS'],
        size: size,
        marks: [
          GuideMark(1, [find.byType(TextField).first]),
          GuideMark(2, [GuideMark.button(find.text('Doanh thu'))]),
          GuideMark(3, [GuideMark.button(find.text('Kết quả kinh doanh'))]),
        ],
      );
    });

    testWidgets('pos-reports-2$suffix: chọn kỳ, xuất Excel', (t) async {
      await guideShot(
        t,
        name: 'pos-reports-2$suffix',
        screen: const PosRevenueReportScreen(),
        api: _api,
        crumbs: const ['Báo cáo POS', 'Doanh thu'],
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.textContaining('Thời gian'))]),
          GuideMark(2, [GuideMark.button(find.byWidgetPredicate((w) => w is ExportFileIcon && w.kind == ExportFileKind.excel))]),
        ],
      );
    });
  }
}
