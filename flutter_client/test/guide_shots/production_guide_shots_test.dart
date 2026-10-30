import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/product_salary_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/production_output_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Sản lượng / lương sản phẩm» (id: production) — xưởng may.

final _groups = [
  {'id': 'g1', 'name': 'Áo sơ mi', 'description': 'Công đoạn may thân áo'},
  {'id': 'g2', 'name': 'Quần tây', 'description': 'May hoàn thiện quần'},
];

final _items = [
  {
    'id': 'i1', 'code': 'SM-01', 'name': 'May cổ áo sơ mi', 'unit': 'cái', 'productGroupId': 'g1', 'productGroupName': 'Áo sơ mi',
    'unitPrice': 2500,
    'priceTiers': [
      {'tierLevel': 1, 'minQuantity': 0, 'maxQuantity': 200, 'unitPrice': 2500},
      {'tierLevel': 2, 'minQuantity': 201, 'maxQuantity': 400, 'unitPrice': 2800},
      {'tierLevel': 3, 'minQuantity': 401, 'maxQuantity': null, 'unitPrice': 3200},
    ],
  },
  {
    'id': 'i2', 'code': 'SM-02', 'name': 'Tra tay áo', 'unit': 'cái', 'productGroupId': 'g1', 'productGroupName': 'Áo sơ mi',
    'unitPrice': 1800,
    'priceTiers': [
      {'tierLevel': 1, 'minQuantity': 0, 'maxQuantity': 300, 'unitPrice': 1800},
      {'tierLevel': 2, 'minQuantity': 301, 'maxQuantity': null, 'unitPrice': 2100},
    ],
  },
  {
    'id': 'i3', 'code': 'QT-01', 'name': 'May lưng quần', 'unit': 'cái', 'productGroupId': 'g2', 'productGroupName': 'Quần tây',
    'unitPrice': 3000,
    'priceTiers': [
      {'tierLevel': 1, 'minQuantity': 0, 'maxQuantity': null, 'unitPrice': 3000},
    ],
  },
];

final _now = DateTime.now();
String _day(int d) => DateTime(_now.year, _now.month, d.clamp(1, 28)).toIso8601String();

Map<String, dynamic> _entry(String id, String emp, String code, String item, String group, num qty, num price, int day,
        [String note = '']) =>
    {
      'id': id, 'workDate': _day(day), 'employeeId': 'e-$code', 'employeeName': emp, 'employeeCode': code,
      'productGroupName': group, 'productItemName': item, 'quantity': qty, 'unitPrice': price, 'amount': qty * price, 'note': note,
    };

final _entries = [
  _entry('p1', 'Nguyễn Thị Hằng', 'NV011', 'May cổ áo sơ mi', 'Áo sơ mi', 220, 2800, 14, 'Ca sáng'),
  _entry('p2', 'Trần Văn Phúc', 'NV012', 'Tra tay áo', 'Áo sơ mi', 310, 2100, 14),
  _entry('p3', 'Lê Thị Thu', 'NV013', 'May lưng quần', 'Quần tây', 150, 3000, 14),
  _entry('p4', 'Nguyễn Thị Hằng', 'NV011', 'May cổ áo sơ mi', 'Áo sơ mi', 190, 2500, 13),
  _entry('p5', 'Phạm Minh Tú', 'NV014', 'Tra tay áo', 'Áo sơ mi', 260, 1800, 13, 'Tăng ca tối'),
  _entry('p6', 'Lê Thị Thu', 'NV013', 'May lưng quần', 'Quần tây', 140, 3000, 13),
];

final _summary = [
  {
    'employeeId': 'e-NV011', 'employeeName': 'Nguyễn Thị Hằng', 'employeeCode': 'NV011', 'totalQuantity': 410, 'totalAmount': 1091000,
    'items': [{'productName': 'May cổ áo sơ mi', 'groupName': 'Áo sơ mi', 'quantity': 410, 'amount': 1091000}],
  },
  {
    'employeeId': 'e-NV012', 'employeeName': 'Trần Văn Phúc', 'employeeCode': 'NV012', 'totalQuantity': 310, 'totalAmount': 651000,
    'items': [{'productName': 'Tra tay áo', 'groupName': 'Áo sơ mi', 'quantity': 310, 'amount': 651000}],
  },
];

final _api = guideApi({
  '/api/production/groups': _groups,
  '/api/production/items': _items,
  '/api/production/entries': {'items': _entries, 'total': _entries.length},
  '/api/production/summary': _summary,
  '/api/branches/select': [],
  '/api/employees': {
    'items': [
      for (final (c, n) in [('NV011', 'Nguyễn Thị Hằng'), ('NV012', 'Trần Văn Phúc'), ('NV013', 'Lê Thị Thu'), ('NV014', 'Phạm Minh Tú')])
        {'id': 'e-$c', 'employeeCode': c, 'fullName': n},
    ],
  },
});

/// Thẻ gần nhất chứa [f].
Finder _card(Finder f) => find.ancestor(of: f, matching: find.byWidgetPredicate((w) => w is Card || w is DecoratedBox)).first;

void _dump(String tag) {
  if (Platform.environment['GUIDE_DUMP'] != '1') return;
  // ignore: avoid_print
  print('DUMP $tag ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(140).toList()}');
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('production-1$suffix: nhóm SP, đơn giá theo bậc', (t) async {
      await guideShot(
        t,
        name: 'production-1$suffix',
        screen: const ProductSalarySettingsScreen(),
        api: _api,
        crumbs: const ['Cài đặt', 'Lương sản phẩm'],
        size: size,
        act: (t) async => _dump('product-salary'),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tất cả').first), find.text('Quần tây').first], pad: 6),
          GuideMark(2, [_card(find.text('May cổ áo sơ mi').first)], pad: 2),
        ],
      );
    });

    testWidgets('production-2$suffix: nhập sản lượng theo ngày / NV', (t) async {
      await guideShot(
        t,
        name: 'production-2$suffix',
        screen: const ProductionOutputScreen(),
        api: _api,
        crumbs: const ['Sản lượng'],
        size: size,
        act: (t) async => _dump('production'),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Nhập sản lượng').last)], pad: 4),
          GuideMark(2, [
            if (size.width < 600) _card(find.text('Nguyễn Thị Hằng').first) else ...[
              find.text('14/10/2026').first,
              find.text('Ca sáng').first,
            ],
          ], pad: 6),
          GuideMark(3, [GuideMark.button(find.text('Chi tiết')), GuideMark.button(find.text('Tổng hợp'))], pad: 4),
        ],
      );
    });
  }
}
