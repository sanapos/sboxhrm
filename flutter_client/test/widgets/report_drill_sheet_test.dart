import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/reports/report_drill_sheet.dart';

Widget _host(void Function(BuildContext) open) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => open(context), child: const Text('mở'))),
        ),
      ),
    );

void main() {
  testWidgets('chip «Nhân viên nghỉ» liệt kê đúng các dòng + số đếm + dòng tổng', (tester) async {
    await tester.pumpWidget(_host((c) => showReportDrillSheet(
          c,
          title: 'Nhân viên nghỉ',
          note: 'Chỉ tính đơn đã duyệt',
          total: 'Tổng 5 ngày',
          rows: const [
            ReportDrillRow(title: 'Nguyễn An', trailing: '2 ngày'),
            ReportDrillRow(title: 'Trần Bình', trailing: '3 ngày'),
          ],
        )));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Nhân viên nghỉ (2)'), findsOneWidget);
    expect(find.text('Nguyễn An'), findsOneWidget);
    expect(find.text('Trần Bình'), findsOneWidget);
    expect(find.text('Chỉ tính đơn đã duyệt'), findsOneWidget);
    expect(find.text('Tổng 5 ngày'), findsOneWidget);
  });

  testWidgets('tải từ API: lỗi thì có nút thử lại, thử lại thành công thì hiện dòng', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host((c) => showReportDrillSheet(
          c,
          title: 'Số phiếu chi',
          load: () async {
            calls++;
            if (calls == 1) throw Exception('mạng');
            return const [ReportDrillRow(title: 'CH-0001', trailing: '150.000 đ')];
          },
        )));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Không tải được dữ liệu'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Số phiếu chi (1)'), findsOneWidget);
    expect(find.text('CH-0001'), findsOneWidget);
  });

  testWidgets('danh sách dài có ô tìm, lọc theo tên', (tester) async {
    await tester.pumpWidget(_host((c) => showReportDrillSheet(
          c,
          title: 'Nhân viên',
          rows: [for (var i = 0; i < 12; i++) ReportDrillRow(title: 'Người $i')],
        )));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Người 11');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Người 11'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Người 3'), findsNothing);
  });
}
