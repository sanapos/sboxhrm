import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/media_query_safe_padding.dart';

MediaQueryData _mq(double bottom) => MediaQueryData(
      size: const Size(390, 844),
      padding: EdgeInsets.only(top: 47, bottom: bottom),
      viewPadding: EdgeInsets.only(top: 47, bottom: bottom),
    );

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iPhone: thanh vuốt 34pt chỉ chừa 18pt thay vì 38pt', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(mediaQueryWithSystemPadding(_mq(34)).padding.bottom, 18);
    // iPad (20pt) và iPhone ngang (21pt): vẫn né vạch vuốt.
    expect(mediaQueryWithSystemPadding(_mq(20)).padding.bottom, 12);
    expect(mediaQueryWithSystemPadding(_mq(21)).padding.bottom, 12);
    // Đầu trên giữ nguyên.
    expect(mediaQueryWithSystemPadding(_mq(34)).padding.top, 47);
  });

  test('Android giữ như cũ: thanh điều hướng + 4', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(mediaQueryWithSystemPadding(_mq(48)).padding.bottom, 52);
  });

  testWidgets('padAwaySystemBars trên iPhone đệm 18pt dưới', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final key = GlobalKey();
    await tester.pumpWidget(MediaQuery(
      data: mediaQueryWithSystemPadding(_mq(34)),
      child: Builder(
        builder: (ctx) => padAwaySystemBars(ctx, SizedBox.expand(key: key)),
      ),
    ));
    final box = tester.getRect(find.byKey(key));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(screen.height - box.bottom, 18);
    debugDefaultTargetPlatformOverride = null;
  });
}
