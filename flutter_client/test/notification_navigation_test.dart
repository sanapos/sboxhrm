import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/navigation_notifier.dart';
import 'package:zkteco_flutter_client/utils/notification_navigation.dart';

void main() {
  tearDown(() {
    notificationShellHandler = null;
    NavigationNotifier.pendingOpenPosQuoteId = null;
    NavigationNotifier.navigateToModule.value = null;
    NavigationNotifier.mainLayoutReady.value = false;
  });

  NotificationNavigationTarget? targetOf(String? type, {String? category, String? title}) {
    final entity = resolveEntityTypeForNotification(
        relatedEntityType: type, categoryCode: category, title: title);
    return resolveNotificationNavigation(entity, title: title);
  }

  test('nhắc hẹn chăm sóc → báo giá (không rơi về hóa đơn bán hàng)', () {
    for (final title in ['Sắp đến hẹn chăm sóc Anh Nam', 'Quá hẹn chăm sóc Công ty ABC']) {
      final t = targetOf('PosQuote', category: 'pos', title: title);
      expect(t?.moduleCode, 'PosQuotes');
      expect(t?.opensPosQuote, isTrue);
    }
  });

  test('cảnh báo hạn sử dụng → báo cáo hàng sắp hết hạn', () {
    final t = targetOf('PosReportExpiry', category: 'pos', title: 'Cảnh báo hạn sử dụng');
    expect(t?.moduleCode, 'PosReportExpiry');
  });

  test('nhóm pos không nhận ra loại → danh sách thông báo, không mở hóa đơn', () {
    expect(targetOf('LoaiMoi', category: 'pos', title: 'Một thông báo lạ'), isNull);
    expect(targetOf('PosSaleOrder', category: 'pos', title: 'Gửi thu ngân')?.moduleCode,
        'PosSaleOrders');
  });

  test('bấm nhắc hẹn trong MainLayout → mở chi tiết đúng báo giá', () {
    NavigationNotifier.mainLayoutReady.value = true;
    navigateFromNotification(
      relatedEntityType: 'PosQuote',
      relatedEntityId: 'q-1',
      title: 'Sắp đến hẹn chăm sóc Anh Nam',
      categoryCode: 'pos',
    );
    expect(NavigationNotifier.pendingOpenPosQuoteId, 'q-1');
    expect(NavigationNotifier.navigateToModule.value, 'PosQuoteDetail');
  });

  test('app bán hàng riêng / Staff (không có MainLayout) → shell tự mở', () {
    String? gotKey;
    String? gotId;
    notificationShellHandler = (key, id) {
      gotKey = key;
      gotId = id;
      return true;
    };
    navigateFromNotification(
        relatedEntityType: 'PosQuote', relatedEntityId: 'q-2', title: 'Quá hẹn chăm sóc X', categoryCode: 'pos');
    expect(gotKey, 'posquote');
    expect(gotId, 'q-2');
    expect(NavigationNotifier.navigateToModule.value, isNull);

    navigateFromNotification(relatedEntityType: 'LoaiMoi', title: 'Một thông báo lạ', categoryCode: 'pos');
    expect(gotKey, isNull);
  });
}
