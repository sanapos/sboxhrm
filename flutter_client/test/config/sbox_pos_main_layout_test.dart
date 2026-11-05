import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/config/sbox_app_variant.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/theme/sbox_tokens.dart';
import 'package:zkteco_flutter_client/utils/permission_navigation.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_theme.dart';

/// Chạy: flutter test --dart-define=SBOX_POS_STANDALONE=true test/config/sbox_pos_main_layout_test.dart
void main() {
  final skipPos = SboxAppVariant.standalonePos ? false : 'cần --dart-define=SBOX_POS_STANDALONE=true';
  final skipHrm = SboxAppVariant.standalonePos ? 'chỉ chạy bản HRM' : false;

  bool allowed(String code) => PermissionNavigation.isAllowedByPackageOrRole(
        code,
        allowedModules: const ['Employee', 'Payroll', 'PosSell', 'CashTransaction'],
        perm: PermissionProvider(),
        bypassPackageFilter: false,
      );

  test('SBOX POS dùng khung của HRM trên mọi cỡ màn, màu thương hiệu xanh lá', () {
    expect(SboxAppVariant.posUsesMainLayout, isTrue);
    expect(SboxColors.brand500, const Color(SboxAppVariant.posGreen));
    expect(PosTheme.kiotBlue, SboxColors.brand600);
  }, skip: skipPos);

  test('chức năng nhân sự bị ẩn dù gói có, chức năng bán hàng và thu chi vẫn còn', () {
    expect(allowed('Employee'), isFalse);
    expect(allowed('Payroll'), isFalse);
    expect(allowed('PosSell'), isTrue);
    expect(allowed('CashTransaction'), isTrue);
    expect(
      PermissionNavigation.isAllowedByPackageOrRole('Attendance',
          allowedModules: null, perm: PermissionProvider(), bypassPackageFilter: true),
      isFalse,
      reason: 'SuperAdmin cũng không thấy mục nhân sự trong app POS',
    );
  }, skip: skipPos);

  test('chữ HRM đổi sang SBOX POS, email hỗ trợ giữ nguyên', () {
    expect(SboxAppVariant.rebrand('Nhập từ thư mục SBOX HRM'), 'Nhập từ thư mục SBOX POS');
    expect(SboxAppVariant.rebrand('Thiết lập HRM'), 'Thiết lập SBOX');
    expect(SboxAppVariant.rebrand('sboxhrm@gmail.com'), 'sboxhrm@gmail.com');
    expect(SboxAppVariant.exportFolderName, 'SBOX POS');
  }, skip: skipPos);

  test('bản HRM giữ nguyên menu nhân sự và chữ HRM', () {
    expect(SboxAppVariant.posUsesMainLayout, isFalse);
    expect(SboxColors.brand500, const Color(0xFF158DC0));
    expect(allowed('Employee'), isTrue);
    expect(SboxAppVariant.rebrand('Thiết lập HRM'), 'Thiết lập HRM');
    expect(SboxAppVariant.exportFolderName, 'SBOX HRM');
  }, skip: skipHrm);
}
