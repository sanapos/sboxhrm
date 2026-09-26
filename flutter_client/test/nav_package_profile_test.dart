import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/mobile_bottom_nav_config.dart';
import 'package:zkteco_flutter_client/utils/nav_package_profile.dart';

MobileBottomNavLayout resolve(Set<String> allowed, {List<String>? stored}) {
  final kind = NavPackageProfile.detect(allowed);
  final defaults = NavPackageProfile.defaultMainSlots(kind);
  return MobileBottomNavLayout(slots: stored ?? defaults).normalized(
    defaultSlots: defaults,
    allowedIds: {...allowed, '_drawer'},
    fallbackOrder: NavPackageProfile.mainPriority(kind),
  );
}

void main() {
  test('Gói chấm công: có đủ công cụ chính, không ô trống', () {
    final r = resolve({'Home', 'MobileAttendance', 'Leave', 'Payslip', 'Task', 'SettingsHub'});
    expect(r.slots, ['Home', 'Leave', 'MobileAttendance', 'Payslip', '_drawer']);
  });

  test('Gói POS: bán hàng ở giữa, không ô trống', () {
    final r = resolve({'Home', 'PosSell', 'PosProducts', 'PosSaleOrders', 'PosSalesReport'});
    expect(r.slots, ['Home', 'PosProducts', 'PosSell', 'PosSaleOrders', '_drawer']);
  });

  test('Bố cục cửa hàng tự đặt: ô mất quyền được lấp theo ưu tiên, ô cố ý trống giữ nguyên', () {
    final r = resolve(
      {'Home', 'MobileAttendance', 'Leave', 'Payslip', 'Task'},
      stored: ['Home', 'PosSell', 'MobileAttendance', '_empty', '_drawer'],
    );
    expect(r.slots, ['Home', 'Leave', 'MobileAttendance', '_empty', '_drawer']);
  });

  test('Nhận loại gói', () {
    expect(NavPackageProfile.detect({'PosSell', 'MobileAttendance'}), NavPackageKind.full);
    expect(NavPackageProfile.detect({'PosSell'}), NavPackageKind.pos);
    expect(NavPackageProfile.detect({'Leave'}), NavPackageKind.attendance);
  });
}
