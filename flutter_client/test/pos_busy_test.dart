import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_busy.dart';

void main() {
  testWidgets('hộp hỏi người dùng (suspend) không bị lớp chờ đè lên; xong thì lớp chờ hiện lại', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));

    final ask = Completer<void>();
    final work = Completer<void>();
    final run = PosBusy.run<void>(ctx, () async {
      await PosBusy.suspend(() => ask.future); // như hộp «Có đóng dấu không?»
      await work.future; // việc nặng sau đó
    }, label: 'Đang dựng…');

    // Quá 120ms trong lúc hộp đang chờ người dùng: KHÔNG được có vòng quay chặn.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    ask.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // đang xử lý → hiện lại

    work.complete();
    await run;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('hideLayer trước 120ms thì lớp chờ không bật lại', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));
    final done = Completer<void>();
    final run = PosBusy.run<void>(ctx, () async {
      PosBusy.hideLayer();
      await done.future;
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    done.complete();
    await run;
  });
}
