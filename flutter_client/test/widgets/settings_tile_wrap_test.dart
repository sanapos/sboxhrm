import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/settings/settings_page.dart';

/// Hàng nút chọn (Wrap) cùng hàng với nhãn trên màn rộng từng ép nhãn còn ~0 điểm → mỗi dòng một chữ
/// («Người nhận», «Các mục trong bản tin» ở Trợ lý AI → Bản tin sáng tự động).
void main() {
  for (final width in [1280.0, 390.0]) {
    testWidgets('SettingsTile với hàng nút chọn: nhãn giữ trên một dòng (rộng $width)', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width > 600 ? width - 260 : width - 32,
            child: SettingsTile(
              label: 'Người nhận',
              help: 'Mỗi người chỉ thấy mục mình có quyền xem',
              control: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in ['Chủ cửa hàng / Admin', 'Quản lý / Giám đốc / Trưởng phòng', 'Kế toán',
                  'Mọi người xem được báo cáo bán hàng'])
                  FilterChip(label: Text(t), selected: true, onSelected: (_) {}),
              ]),
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      final label = tester.getSize(find.text('Người nhận'));
      expect(label.height, lessThan(30), reason: 'nhãn bị vỡ thành nhiều dòng: $label');
      expect(label.width, greaterThan(50));
    });
  }
}
