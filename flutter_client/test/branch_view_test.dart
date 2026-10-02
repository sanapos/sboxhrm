import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';
import 'package:zkteco_flutter_client/services/branch_session.dart';
import 'package:zkteco_flutter_client/utils/branch_filter_helper.dart';
import 'package:zkteco_flutter_client/widgets/branch_switcher.dart';

/// Chi nhánh đang làm việc = chi nhánh đang xem: "Tất cả chi nhánh", mặc định, header gửi server.
/// Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
  }
}

Map<String, dynamic> _ctx({bool canSeeAll = true, String? current}) => {
      'isSuccess': true,
      'data': {
        'usesBranches': true,
        'canSeeAllBranches': canSeeAll,
        'headquarterBranchId': 'hq',
        'currentBranchId': current,
        'branches': [
          {'id': 'hq', 'code': 'HQ', 'name': 'Trụ sở Quận 1', 'isHeadquarter': true, 'isActive': true},
          {'id': 'b2', 'code': 'Q7', 'name': 'Chi nhánh Quận 7', 'isHeadquarter': false, 'isActive': true},
          {'id': 'b3', 'code': 'TD', 'name': 'Chi nhánh Thủ Đức', 'isHeadquarter': false, 'isActive': true},
        ],
      },
    };

Future<void> _load(Map<String, dynamic> ctx) async {
  final client = MockClient((req) async =>
      http.Response(jsonEncode(ctx), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
  await http.runWithClient(() => BranchSession.instance.load(), () => client);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name, double ratio) async {
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BranchSession.instance.clear();
  });

  test('Mặc định: người xem toàn cửa hàng - tất cả; nhân viên - chi nhánh của mình; nhớ lựa chọn', () {
    const ids = ['hq', 'b2'];
    expect(BranchSession.resolveInitial(saved: null, serverCurrent: 'b2', branchIds: ids, canSeeAll: true),
        BranchSession.allId);
    expect(BranchSession.resolveInitial(saved: null, serverCurrent: 'b2', branchIds: ids, canSeeAll: false), 'b2');
    expect(BranchSession.resolveInitial(saved: 'hq', serverCurrent: 'b2', branchIds: ids, canSeeAll: true), 'hq');
    expect(
        BranchSession.resolveInitial(
            saved: BranchSession.allId, serverCurrent: 'b2', branchIds: ids, canSeeAll: false),
        BranchSession.allId);
    // Lựa chọn cũ không còn hợp lệ - về mặc định
    expect(BranchSession.resolveInitial(saved: 'gone', serverCurrent: 'b2', branchIds: ids, canSeeAll: false), 'b2');
    // 1 chi nhánh - không có "tất cả"
    expect(
        BranchSession.resolveInitial(
            saved: BranchSession.allId, serverCurrent: null, branchIds: ['hq'], canSeeAll: true),
        'hq');
  });

  test('Tất cả chi nhánh: không lọc khi xem, ghi về trụ sở, header "all"', () async {
    await _load(_ctx());
    final s = BranchSession.instance;
    expect(s.isAll, isTrue);
    expect(s.viewBranchId, isNull);
    expect(s.writeBranchId, 'hq');
    expect(s.currentLabel, 'Tất cả chi nhánh');
    expect(ApiService.currentBranchId, 'all');

    await s.select('b2');
    expect(s.isAll, isFalse);
    expect(s.viewBranchId, 'b2');
    expect(s.writeBranchId, 'b2');
    expect(ApiService.currentBranchId, 'b2');
    expect(BranchFilterHelper.viewBranchId, 'b2');
    expect((await SharedPreferences.getInstance()).getString('branch_session_current'), 'b2');
  });

  test('Nhân viên chi nhánh mặc định xem chi nhánh của mình', () async {
    await _load(_ctx(canSeeAll: false, current: 'b3'));
    expect(BranchSession.instance.viewBranchId, 'b3');
    expect(ApiService.currentBranchId, 'b3');
  });

  test('Bộ lọc chi nhánh riêng của màn hình ẩn khi đã có bộ chọn chung', () async {
    final list = [
      {'id': 'a'},
      {'id': 'b'}
    ];
    expect(BranchFilterHelper.showBranchFilter(list), isTrue); // cửa hàng chưa dùng chi nhánh: giữ cũ
    await _load(_ctx());
    expect(BranchFilterHelper.showBranchFilter(list), isFalse);
    expect(BranchFilterHelper.hasMultipleBranches(list), isTrue); // cột / nhóm theo chi nhánh vẫn còn
  });

  Future<void> pumpShell(WidgetTester tester, GlobalKey key, Size size, Widget child) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider().lightTheme,
        home: MediaQuery(data: MediaQueryData(size: size), child: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Điện thoại: dòng "Đang xem" + chọn chi nhánh', (tester) async {
    await tester.runAsync(() => _load(_ctx()));
    final key = GlobalKey();
    await pumpShell(
      tester,
      key,
      const Size(390, 640),
      Scaffold(
        appBar: AppBar(title: const Text('Chấm công'), toolbarHeight: 44),
        body: const Column(children: [
          BranchViewStrip(),
          Expanded(child: Center(child: Text('Dữ liệu chấm công của chi nhánh đang xem'))),
        ]),
      ),
    );
    expect(find.text('Tất cả chi nhánh'), findsOneWidget);
    expect(find.text('Đổi'), findsOneWidget);
    await _shot(tester, key, 'branch_mobile_strip', 2);

    await tester.tap(find.text('Đổi'));
    await tester.pumpAndSettle();
    expect(find.text('Chi nhánh Quận 7'), findsOneWidget);
    await _shot(tester, key, 'branch_mobile_sheet', 2);

    await tester.tap(find.text('Chi nhánh Quận 7'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(BranchSession.instance.viewBranchId, 'b2');
    expect(find.text('Chi nhánh Quận 7'), findsOneWidget);
    await _shot(tester, key, 'branch_mobile_selected', 2);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Máy tính: bộ chọn trên đầu có "Tất cả chi nhánh"', (tester) async {
    await tester.runAsync(() => _load(_ctx()));
    final key = GlobalKey();
    await pumpShell(
      tester,
      key,
      const Size(1280, 520),
      Scaffold(
        appBar: AppBar(title: const Text('Bảng lương'), actions: const [BranchSwitcher(), SizedBox(width: 16)]),
        body: const Center(child: Text('Bảng lương - lọc theo chi nhánh đang xem')),
      ),
    );
    await tester.tap(find.byType(BranchSwitcher));
    await tester.pumpAndSettle();
    expect(find.text('Tất cả chi nhánh'), findsNWidgets(2));
    expect(find.text('Trụ sở'), findsOneWidget);
    await _shot(tester, key, 'branch_desktop_menu', 1.25);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
