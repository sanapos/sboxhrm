import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';

/// Dữ liệu mẫu + helper dùng chung cho ảnh hướng dẫn «Tài sản / Công việc / Công tác / Chấm cơm / Bản đồ».

Map<String, dynamic> extrasEmployee(String id, String code, String last, String first, String dept, String pos) => {
      'id': id, 'employeeCode': code, 'pin': code, 'lastName': last, 'firstName': first,
      'fullName': '$last $first', 'department': dept, 'position': pos, 'workStatus': 'Active',
      'joinDate': '2024-03-01T00:00:00', 'phoneNumber': '09031234${code.padLeft(2, '0')}', 'branchName': 'Cơm Gà Nam',
    };

final extrasEmployees = [
  extrasEmployee('e1', '1', 'Nguyễn Văn', 'Hùng', 'Ban quản lý', 'Chủ cửa hàng'),
  extrasEmployee('e2', '2', 'Trần Thị', 'Lan', 'Phục vụ', 'Trưởng ca'),
  extrasEmployee('e3', '3', 'Lê Văn', 'Minh', 'Bếp', 'Bếp trưởng'),
  extrasEmployee('e4', '4', 'Phạm Thị', 'Hoa', 'Thu ngân', 'Thu ngân'),
  extrasEmployee('e5', '5', 'Võ Minh', 'Tuấn', 'Phục vụ', 'Nhân viên phục vụ'),
  extrasEmployee('e8', '8', 'Hồ Ngọc', 'Ánh', 'Kế toán', 'Kế toán viên'),
];

/// Gói có các module HRM mở rộng — user của kit không có allowedModules nên màn Công việc,
/// Công tác phí, Chấm cơm… coi như gói không có và không tải dữ liệu.
const extrasModules = ['Task', 'Asset', 'BusinessTripExpense', 'Meal', 'StaffMap', 'Employee', 'Department'];

Widget withExtrasPackage(Widget child) {
  // Tạo AuthProvider trước khi kit giả SharedPreferences → khôi phục phiên lỗi và xóa user.
  SharedPreferences.setMockInitialValues({});
  final auth = AuthProvider()
    ..debugSetUser(User(
      id: 'u1',
      employeeId: 'e1',
      email: 'admin@comganam.vn',
      fullName: 'Nguyễn Văn Hùng',
      role: 'Admin',
      storeId: 's1',
      allowedModules: extrasModules,
    ));
  return ChangeNotifierProvider<AuthProvider>.value(value: auth, child: child);
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

/// Ô nhập có nhãn [label] (InputDecoration.labelText).
Finder fieldLabeled(String label) => find.ancestor(of: find.text(label), matching: find.byType(TextField)).first;

/// Cả ô chọn (DropdownButtonFormField) có nhãn [label].
Finder dropdownLabeled(String label) => find
    .ancestor(of: find.text(label).last, matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField))
    .first;

/// Khung nhập (InputDecorator) có nhãn [label] — ô chọn ngày, ô chọn người…
Finder decoratorLabeled(String label) =>
    find.ancestor(of: find.text(label).last, matching: find.byType(InputDecorator)).first;

/// Nút trên thanh đầu trang: máy tính chỉ vẽ biểu tượng + tooltip (khi không showLabel),
/// điện thoại vẽ nút FAB có chữ.
Finder topAction(String label) => find
    .byWidgetPredicate((w) => (w is Text && w.data == label) || (w is Tooltip && w.message == label))
    .first;

/// Khung đánh dấu cho nút thanh đầu trang: máy tính = vùng tooltip của biểu tượng,
/// điện thoại = cả nút FAB.
Finder topActionBox(String label, {required bool mobile}) => mobile
    ? find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is InkResponse)).first
    : find.byWidgetPredicate((w) => w is Tooltip && w.message == label).first;

/// Thẻ (khung có viền) gần nhất chứa [f] — để khung đánh dấu bao trọn thẻ thay vì một dòng chữ.
Finder cardOf(Finder f) => find
    .ancestor(
        of: f,
        matching: find.byWidgetPredicate(
            (w) => w is Card || (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null)))
    .first;

Future<void> extrasSettle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Cuộn vùng cuộn chứa [f] để [f] nằm ở [alignment] (dùng được trong hộp thoại).
Future<void> scrollInto(WidgetTester t, Finder f, {double alignment = 0.2}) async {
  await Scrollable.ensureVisible(t.element(f.first), alignment: alignment);
  await t.pump();
}

String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
