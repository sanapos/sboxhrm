import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/settings_screen.dart';

import 'guide_shot_kit.dart';

// Dòng «Gói dịch vụ» trong Cài đặt: chủ cửa hàng xem còn bao nhiêu ngày sử dụng.
// Chạy kèm ảnh: GUIDE_SHOT_DIR=… GUIDE_SHOT_PLAIN=1 flutter test test/guide_shots/settings_license_test.dart

String _inDays(int days) =>
    DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

Map<String, Object?> _api(Object? license) => {
      '/api/store/license-status': license,
      '/api/zalo-bot/me': {'available': false, 'linked': false},
    };

/// Màn Cài đặt đọc ThemeProvider (chọn sáng/tối); bộ dựng ảnh chỉ cấp Auth + Permission.
Widget _screen() => ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SettingsScreen(),
    );

void main() {
  testWidgets('settings-license-1: gói còn hạn dài — không tô màu', (t) async {
    await guideShot(t,
        name: 'settings-license-1',
        screen: _screen(),
        api: guideApi(_api({
          'isExpired': false,
          'isActive': true,
          'expiryDate': _inDays(210),
          'effectiveExpiryDate': _inDays(210),
          'daysLeft': 210,
          'isTrial': false,
          'packageName': 'Chuyên nghiệp',
        })), act: (t) async {
      await guideScrollTo(t, find.text('Gói dịch vụ'), alignment: 0.4);
      expect(find.text('Gói dịch vụ'), findsOneWidget);
      expect(find.textContaining('Còn 210 ngày'), findsOneWidget);
      expect(find.textContaining('Chuyên nghiệp'), findsOneWidget);
    });
  });

  testWidgets('settings-license-2: bản dùng thử sắp hết — có cảnh báo', (t) async {
    await guideShot(t,
        name: 'settings-license-2',
        screen: _screen(),
        api: guideApi(_api({
          'isExpired': false,
          'isActive': true,
          'expiryDate': null,
          'effectiveExpiryDate': _inDays(5),
          'daysLeft': 5,
          'isTrial': true,
          'packageName': 'Cơ bản',
        })), act: (t) async {
      await guideScrollTo(t, find.text('Gói dịch vụ'), alignment: 0.4);
      // Cửa hàng dùng thử: endpoint cũ trả expiryDate = null nên không hiện gì;
      // giờ lấy hạn cuối kỳ dùng thử nên vẫn đếm được ngày.
      expect(find.textContaining('Còn 5 ngày'), findsOneWidget);
      expect(find.textContaining('dùng thử'), findsOneWidget);
    });
  });

  testWidgets('settings-license-3: đã hết hạn', (t) async {
    await guideShot(t,
        name: 'settings-license-3',
        screen: _screen(),
        api: guideApi(_api({
          'isExpired': true,
          'isActive': true,
          'expiryDate': _inDays(-3),
          'effectiveExpiryDate': _inDays(-3),
          'daysLeft': -3,
          'isTrial': false,
          'packageName': 'Nâng cao',
          'message': 'Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.',
        })), act: (t) async {
      await guideScrollTo(t, find.text('Gói dịch vụ'), alignment: 0.4);
      expect(find.text('Đã hết hạn'), findsOneWidget);
    });
  });
}
