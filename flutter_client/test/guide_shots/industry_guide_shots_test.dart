import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/activity_log_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_sell_industry_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/pos_print_templates_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho tab Ngành hàng: chọn ngành (ind_choose), bán lẻ / siêu thị (ind_retail),
/// mẫu Word & lịch sử thao tác (ind_docs_log) — cửa hàng tạp hóa «Tạp hóa Minh Châu».

Map<String, Object?> _sell({bool scale = false}) => {
      'id': 'ss1',
      'sellProfile': 'retail',
      'defaultSellMode': 'quick',
      'allowNegativeStock': false,
      'enableCashierShift': true,
      'loyaltyEnabled': true,
      if (scale)
        'extraJson': jsonEncode({
          'scale': {'enabled': true, 'prefixes': ['20', '21'], 'pluDigits': 5, 'mode': 'weight', 'decimals': 3},
        }),
    };

const _receiptHtml = '<div style="text-align:center"><b>TẠP HÓA MINH CHÂU</b><br>48 Lê Văn Sỹ, Q.3<br>'
    '<b>HÓA ĐƠN BÁN HÀNG</b><br>Số: {Ma_Don_Hang}</div><table>{Chi_Tiet_Hang}</table>'
    '<div style="text-align:right"><b>Tổng cộng: {Tong_Tien}</b></div>';

final _logs = [
  {
    'id': 'l1', 'timestamp': '2026-10-30T16:42:00', 'action': 'Update', 'userName': 'Trần Thị Mai',
    'userEmail': 'mai@minhchau.vn', 'userRole': 'Thu ngân', 'moduleName': 'Hàng hóa', 'module': 'PosProducts',
    'entityName': 'Sữa tươi Vinamilk 1L', 'fieldCount': 1, 'device': 'Máy POS quầy 1',
  },
  {
    'id': 'l2', 'timestamp': '2026-10-30T15:10:00', 'action': 'Delete', 'userName': 'Lê Văn Hùng',
    'userEmail': 'hung@minhchau.vn', 'userRole': 'Quản lý', 'moduleName': 'Đơn hàng', 'module': 'PosSaleOrders',
    'entityName': 'Đơn HD000215 (khách đổi ý)', 'fieldCount': 0, 'device': 'Web',
  },
  {
    'id': 'l3', 'timestamp': '2026-10-30T09:05:00', 'action': 'Create', 'userName': 'Trần Thị Mai',
    'userEmail': 'mai@minhchau.vn', 'userRole': 'Thu ngân', 'moduleName': 'Khách hàng', 'module': 'PosCustomers',
    'entityName': 'Chị Hoa — 0903 456 789', 'fieldCount': 4, 'device': 'Máy POS quầy 1',
  },
  {
    'id': 'l4', 'timestamp': '2026-10-29T18:30:00', 'action': 'Update', 'userName': 'Lê Văn Hùng',
    'userEmail': 'hung@minhchau.vn', 'userRole': 'Quản lý', 'moduleName': 'Thiết lập bán hàng', 'module': 'PosSell',
    'entityName': 'Ngành hàng & cách bán', 'fieldCount': 2, 'device': 'Web',
  },
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/sell-settings')) return _sell(scale: true);
  if (p.endsWith('/api/pos/print-templates')) {
    final type = req.url.queryParameters['documentType'] ?? 'Invoice';
    return [
      {'id': 't1', 'name': 'Hóa đơn K80 — Minh Châu', 'documentType': type, 'paperSize': 'K80',
        'htmlContent': _receiptHtml, 'isDefault': true, 'isActive': true, 'sortOrder': 0},
    ];
  }
  if (p.endsWith('/api/activity-logs/filters')) {
    return {
      'users': [
        {'userId': 'u2', 'name': 'Trần Thị Mai', 'count': 2},
        {'userId': 'u3', 'name': 'Lê Văn Hùng', 'count': 2},
      ],
      'modules': [
        {'code': 'PosProducts', 'name': 'Hàng hóa', 'count': 1},
        {'code': 'PosSaleOrders', 'name': 'Đơn hàng', 'count': 1},
        {'code': 'PosCustomers', 'name': 'Khách hàng', 'count': 1},
        {'code': 'PosSell', 'name': 'Thiết lập bán hàng', 'count': 1},
      ],
    };
  }
  if (p.endsWith('/api/activity-logs/l1')) {
    return {
      ..._logs.first,
      'ipAddress': '192.168.1.20',
      'details': {
        'changes': [
          {
            'op': 'Update', 'typeName': 'Hàng hóa', 'label': 'Sữa tươi Vinamilk 1L',
            'fields': [
              {'field': 'basePrice', 'fieldName': 'Giá bán', 'old': '32.000', 'new': '34.000'},
            ],
          },
        ],
      },
    };
  }
  if (p.endsWith('/api/activity-logs')) {
    return {'items': _logs, 'total': _logs.length, 'creates': 1, 'updates': 2, 'deletes': 1};
  }
  return null;
});

/// Ô chọn có nhãn [label] (khung bao trọn ô, không chỉ chữ nhãn).
Finder _dropdown(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)).first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    const indCrumbs = ['Thiết lập SBOX', 'Ngành hàng & cách bán'];

    testWidgets('ind-choose-1$suffix: danh sách ngành', (t) async {
      await guideShot(
        t,
        name: 'ind-choose-1$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: indCrumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Chọn ngành hàng'), alignment: 0.02),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Bán lẻ / Siêu thị'))]),
          GuideMark(2, [GuideMark.button(find.text('Nhà hàng / Cafe'))]),
        ],
      );
    });

    testWidgets('ind-choose-2$suffix: xác nhận đổi ngành', (t) async {
      await guideShot(
        t,
        name: 'ind-choose-2$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: indCrumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Nhà hàng / Cafe'), alignment: 0.4);
          await t.tap(find.text('Nhà hàng / Cafe'));
          await t.pump(const Duration(milliseconds: 500));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Đổi ngành'))]),
        ],
      );
    });

    testWidgets('ind-choose-3$suffix: bật / tắt từng tính năng', (t) async {
      await guideShot(
        t,
        name: 'ind-choose-3$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: indCrumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Hoa hồng nhân viên'), alignment: 0.12),
        marks: [
          GuideMark(1, [find.text('Hoa hồng nhân viên')]),
          GuideMark(2, [find.text('Gói buổi / liệu trình / thẻ tập')]),
          GuideMark(3, [find.text('Cho phép tạm tính')]),
        ],
      );
    });

    testWidgets('ind-retail-1$suffix: bán nhanh', (t) async {
      await guideShot(
        t,
        name: 'ind-retail-1$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: indCrumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Chế độ bán mặc định'), alignment: 0.3),
        marks: [
          GuideMark(1, [find.text('Chế độ bán mặc định'), find.byType(DropdownButtonFormField<String>).first]),
        ],
      );
    });

    testWidgets('ind-retail-2$suffix: cân điện tử', (t) async {
      await guideShot(
        t,
        name: 'ind-retail-2$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: indCrumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Đọc mã vạch cân điện tử'), alignment: 0.15),
        marks: [
          GuideMark(1, [find.text('Đọc mã vạch cân điện tử')]),
          // Thứ tự trên màn: số chữ số PLU nằm trên ô đầu mã.
          GuideMark(2, [find.text('Số chữ số mã hàng (PLU)')], pad: 4),
          GuideMark(3, [GuideMark.within(find.text('Đầu mã của cân'), 'TextField')], pad: 4),
        ],
      );
    });

    testWidgets('ind-docs-log-1$suffix: thêm mẫu Word', (t) async {
      await guideShot(
        t,
        name: 'ind-docs-log-1$suffix',
        screen: withPosPackage(const PosPrintTemplatesScreen(embeddedInSettings: true)),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Mẫu in'],
        size: size,
        act: (t) async {
          final add = find.text('Thêm mẫu');
          await t.ensureVisible(add.first);
          await t.tap(add.first);
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tải file Word của bạn'))]),
        ],
      );
    });

    testWidgets('ind-docs-log-2$suffix: lịch sử thao tác', (t) async {
      await guideShot(
        t,
        name: 'ind-docs-log-2$suffix',
        screen: withPosPackage(const ActivityLogScreen()),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Lịch sử thao tác'],
        size: size,
        marks: [
          GuideMark(1, [_dropdown('Người thao tác'), _dropdown('Chức năng')]),
          GuideMark(2, [find.textContaining('Sữa tươi Vinamilk 1L', findRichText: true).first], pad: 10),
          if (!mobile) GuideMark(3, [find.byTooltip('Xuất Excel').first]),
        ],
      );
    });

    testWidgets('ind-docs-log-3$suffix: giá trị trước / sau', (t) async {
      await guideShot(
        t,
        name: 'ind-docs-log-3$suffix',
        screen: withPosPackage(const ActivityLogScreen()),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Lịch sử thao tác'],
        size: size,
        act: (t) async {
          await t.tap(find.textContaining('Sữa tươi Vinamilk 1L', findRichText: true).first);
          await t.pump(const Duration(milliseconds: 300));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 500));
        },
        marks: [
          GuideMark(1, [find.textContaining('Trần Thị Mai').last]),
          GuideMark(2, [find.text('Giá bán').last, find.text('32.000'), find.text('34.000')], pad: 8),
        ],
      );
    });
  }
}
