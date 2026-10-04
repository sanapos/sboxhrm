import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/app_scroll_safe.dart';

void main() {
  testWidgets('Bảng cuộn giữ vị trí khi màn vẽ lại, có đủ 2 thanh cuộn', (t) async {
    late StateSetter rebuild;
    var tick = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 200,
          child: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return AppTableScroll(
              minWidth: 1200,
              child: SizedBox(height: 2000, child: Text('bảng $tick')),
            );
          }),
        ),
      ),
    ));
    final views = t.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).toList();
    final v = views.firstWhere((w) => w.scrollDirection == Axis.vertical).controller!;
    final h = views.firstWhere((w) => w.scrollDirection == Axis.horizontal).controller!;
    v.jumpTo(500);
    h.jumpTo(300);
    await t.pump();

    rebuild(() => tick++);
    await t.pump();

    final after = t.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).toList();
    expect(after.firstWhere((w) => w.scrollDirection == Axis.vertical).controller!.offset, 500);
    expect(after.firstWhere((w) => w.scrollDirection == Axis.horizontal).controller!.offset, 300);
    expect(find.byType(Scrollbar), findsNWidgets(2));
  });
}
