import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/widgets/reports/report_breakdown_sheet.dart';

/// Báo cáo: bộ lọc thu gọn khi mở màn (còn 1 dòng tóm tắt) và bảng chi tiết khi bấm thẻ số liệu.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('bộ lọc thu gọn lúc mở, bấm để mở / thu', (t) async {
    await t.pumpWidget(host(ReportCollapsibleChrome(
      expanded: true, // màn cũ truyền true — khung vẫn thu gọn
      onToggle: () {},
      betweenKpiAndFilter: const [Text('Tối thiểu')],
      filter: ReportFilterSection(
        embedded: true,
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 11),
        datePreset: 'thisMonth',
        onDateChanged: (_, __, ___) {},
        statusFilter: const Text('Ô trạng thái'),
        statusSummary: 'Chờ duyệt',
        showTeamFilters: false,
        onEmpSearchChanged: (_) {},
        onApply: () {},
      ),
    )));
    expect(find.text('Bộ lọc'), findsOneWidget);
    expect(find.textContaining('01/11/26 — 11/11/26'), findsOneWidget);
    expect(find.textContaining('Chờ duyệt'), findsOneWidget);
    expect(find.text('Ô trạng thái'), findsNothing);
    expect(find.text('Tối thiểu'), findsNothing);

    await t.tap(find.text('Bộ lọc'));
    await t.pumpAndSettle();
    expect(find.text('Ô trạng thái'), findsOneWidget);
    expect(find.text('Tối thiểu'), findsOneWidget);

    await t.tap(find.text('Bộ lọc'));
    await t.pumpAndSettle();
    expect(find.text('Ô trạng thái'), findsNothing);
  });

  test('gom theo nhân viên: cộng tiền, đếm phiếu, xếp giảm dần', () {
    final rows = reportGroupBreakdown<Map<String, Object>>(
      [
        {'n': 'An', 'a': 50000},
        {'n': 'Bình', 'a': 100000},
        {'n': 'An', 'a': 70000},
        {'n': '', 'a': 10000},
      ],
      keyOf: (m) => '${m['n']}',
      valueOf: (m) => m['a'] as int,
      captionOf: (c, _) => '$c phiếu',
    );
    expect(rows.map((r) => r.label), ['An', 'Bình', '—']);
    expect(rows.first.value, 120000);
    expect(rows.first.caption, '2 phiếu');
  });

  testWidgets('bảng chi tiết: danh sách, nút lọc đóng bảng rồi gọi lọc', (t) async {
    var filtered = false;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showReportBreakdownSheet(
              ctx,
              title: 'Đã duyệt',
              subtitle: 'Tháng này',
              rows: const [
                ReportBreakdownRow(label: 'Nguyễn An', value: 3, caption: '150.000 đ'),
                ReportBreakdownRow(label: 'Trần Bình', value: 1),
              ],
              actionLabel: 'Lọc danh sách theo mục này',
              onAction: () => filtered = true,
            ),
            child: const Text('mở'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Nguyễn An'), findsOneWidget);
    expect(find.text('150.000 đ'), findsOneWidget);
    await t.tap(find.text('Lọc danh sách theo mục này'));
    await t.pumpAndSettle();
    expect(filtered, isTrue);
    expect(find.text('Nguyễn An'), findsNothing);
  });
}
