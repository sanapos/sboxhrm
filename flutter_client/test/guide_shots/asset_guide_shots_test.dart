import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/asset_management_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Tài sản» (id: asset).

Map<String, dynamic> _a(String id, String code, String name, String type, String cat, String status,
        {required int price, required String bought, int warranty = 12, String? holder, String? holderId, String? location}) =>
    {
      'id': id, 'assetCode': code, 'name': name, 'assetType': type, 'categoryId': cat,
      'categoryName': {'c1': 'Thiết bị bán hàng', 'c2': 'Bếp', 'c3': 'Văn phòng'}[cat],
      'status': status, 'quantity': 1, 'unit': 'Cái', 'purchasePrice': price, 'currentValue': price * 0.8,
      'purchaseDate': '${bought}T00:00:00', 'warrantyMonths': warranty,
      'warrantyExpiry': '${(int.parse(bought.substring(0, 4)) + warranty ~/ 12)}${bought.substring(4)}T00:00:00',
      'daysUntilWarrantyExpiry': 200, 'currentAssigneeId': holderId, 'currentAssigneeName': holder,
      'assignedDate': holder == null ? null : '2026-03-01T00:00:00', 'location': location, 'isActive': true,
      'createdAt': '2026-01-10T03:00:00Z',
    };

final _assets = [
  _a('a1', 'TS-0001', 'Máy POS Sunmi T2', 'Electronics', 'c1', 'Active',
      price: 9800000, bought: '2025-11-20', holder: 'Phạm Thị Hoa', holderId: 'e4', location: 'Quầy thu ngân'),
  _a('a2', 'TS-0002', 'Máy in hóa đơn Xprinter K80', 'Electronics', 'c1', 'Active',
      price: 1650000, bought: '2025-11-20', holder: 'Phạm Thị Hoa', holderId: 'e4', location: 'Quầy thu ngân'),
  _a('a3', 'TS-0003', 'Tủ mát Sanaky 400L', 'Machinery', 'c2', 'Active',
      price: 12500000, bought: '2024-06-02', warranty: 24, holder: 'Lê Văn Minh', holderId: 'e3', location: 'Bếp'),
  _a('a4', 'TS-0004', 'Laptop Dell Vostro 3520', 'Electronics', 'c3', 'InStock', price: 14200000, bought: '2026-09-15', location: 'Kho'),
  _a('a5', 'TS-0005', 'Bếp gas công nghiệp 2 họng', 'Machinery', 'c2', 'InMaintenance',
      price: 4300000, bought: '2023-08-10', location: 'Bếp'),
  _a('a6', 'TS-0006', 'Bộ bàn ghế inox 6 chỗ', 'Furniture', 'c3', 'Active',
      price: 3200000, bought: '2024-02-14', warranty: 6, holder: 'Trần Thị Lan', holderId: 'e2', location: 'Sân vườn'),
];

final _categories = [
  {'id': 'c1', 'categoryCode': 'TBBH', 'name': 'Thiết bị bán hàng', 'assetCount': 2, 'isActive': true, 'createdAt': '2026-01-01T00:00:00Z'},
  {'id': 'c2', 'categoryCode': 'BEP', 'name': 'Bếp', 'assetCount': 2, 'isActive': true, 'createdAt': '2026-01-01T00:00:00Z'},
  {'id': 'c3', 'categoryCode': 'VP', 'name': 'Văn phòng', 'assetCount': 2, 'isActive': true, 'createdAt': '2026-01-01T00:00:00Z'},
];

final _api = guideApi({
  '/api/Assets/statistics': {
    'totalAssets': 6, 'activeAssets': 4, 'inStockAssets': 1, 'assignedAssets': 4, 'maintenanceAssets': 1,
    'brokenAssets': 0, 'disposedAssets': 0, 'totalPurchaseValue': 45650000, 'totalCurrentValue': 36520000,
    'warrantyExpiringSoon': 1,
  },
  '/api/Assets/categories': _categories,
  '/api/Assets/dashboard': {},
  '/api/Assets/transfers': {'items': []},
  '/api/Assets': {'items': _assets, 'totalCount': _assets.length},
  '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
});

const _crumbs = ['Tài sản'];

Future<void> _openAssetsTab(WidgetTester t) async {
  await t.tap(find.text('Tài sản').last);
  await extrasSettle(t);
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('asset-1$suffix: danh sách tài sản', (t) async {
      await guideShot(
        t,
        name: 'asset-1$suffix',
        screen: const AssetManagementScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: _openAssetsTab,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm tài sản'))]),
          GuideMark(2, [find.text('Đang sử dụng').first, find.text('Phạm Thị Hoa').first]),
        ],
      );
    });

    testWidgets('asset-2$suffix: thêm tài sản', (t) async {
      await guideShot(
        t,
        name: 'asset-2$suffix',
        screen: const AssetManagementScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm tài sản'],
        size: size,
        act: (t) async {
          await _openAssetsTab(t);
          await t.tap(find.text('Thêm tài sản').first);
          await extrasSettle(t);
          await t.enterText(fieldLabeled('Tên tài sản *'), 'Máy pha cà phê Delonghi');
          await t.enterText(fieldLabeled('Giá mua *'), '18500000');
          await t.enterText(fieldLabeled('Bảo hành (tháng)'), '24');
          await t.pump();
          await scrollInto(t, fieldLabeled('Tên tài sản *'), alignment: 0.02);
        },
        marks: [
          GuideMark(1, [fieldLabeled('Tên tài sản *')]),
          GuideMark(2, [dropdownLabeled('Loại tài sản'), dropdownLabeled('Danh mục')]),
          GuideMark(3, [fieldLabeled('Giá mua *')]),
        ],
      );
    });

    testWidgets('asset-3$suffix: cấp phát cho nhân viên', (t) async {
      await guideShot(
        t,
        name: 'asset-3$suffix',
        screen: const AssetManagementScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Cấp phát'],
        size: size,
        act: (t) async {
          await _openAssetsTab(t);
          // Danh sách điện thoại dựng dần — cuộn tới dòng Laptop rồi lấy nút «…» cùng hàng.
          await guideScrollTo(t, find.text('Laptop Dell Vostro 3520'), alignment: 0.4);
          final y = t.getCenter(find.text('Laptop Dell Vostro 3520')).dy;
          final menus = find.byType(PopupMenuButton<String>).evaluate().toList()
            ..sort((a, b) => (t.getCenter(find.byWidget(a.widget)).dy - y).abs()
                .compareTo((t.getCenter(find.byWidget(b.widget)).dy - y).abs()));
          await t.tap(find.byWidget(menus.first.widget));
          await extrasSettle(t, 4);
          await t.tap(find.text('Cấp phát').last);
          await extrasSettle(t);
          await t.tap(find.text('Cấp cho *').last);
          await extrasSettle(t, 4);
          await t.tap(find.text('Võ Minh Tuấn · 5').last);
          await extrasSettle(t, 4);
          await t.enterText(fieldLabeled('Lý do'), 'Cấp máy cho ca tối làm sổ sách');
          await t.pump();
        },
        marks: [
          GuideMark(1, [dropdownLabeled('Cấp cho *')]),
          GuideMark(2, [fieldLabeled('Lý do')]),
          GuideMark(3, [GuideMark.button(find.text('Cấp phát').last)]),
        ],
      );
    });
  }
}
