import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_print_role.dart';

({List<String> saved, List<String> toRegister}) reconcile({
  required List<String> assigned,
  List<String> store = const ['a', 'b'],
  List<String>? active,
  bool fresh = true,
  bool keepIfAllMissing = false,
}) =>
    PosPrintRole.reconcileAgentChips(
      assigned: assigned,
      storeIds: store,
      activeIds: active ?? store,
      fresh: fresh,
      keepIfAllMissing: keepIfAllMissing,
    );

void main() {
  test('Máy đang bật: giữ chip và đăng ký, không phân biệt hoa/thường', () {
    final r = reconcile(assigned: ['A', 'b']);
    expect(r.saved, ['A', 'b']);
    expect(r.toRegister, ['A', 'b']);
  });

  test('Tạm tắt máy in: giữ chip nhưng không đăng ký; bật lại là đăng ký', () {
    final off = reconcile(assigned: ['a'], active: ['b']);
    expect(off.saved, ['a']);
    expect(off.toRegister, isEmpty);

    final on = reconcile(assigned: off.saved, active: ['a', 'b']);
    expect(on.toRegister, ['a']);
  });

  test('Tắt một trong hai máy: chỉ đăng ký máy còn bật', () {
    final r = reconcile(assigned: ['a', 'b'], active: ['b']);
    expect(r.saved, ['a', 'b']);
    expect(r.toRegister, ['b']);
  });

  test('Máy đã xóa: danh sách vừa tải xác nhận thì bỏ chip', () {
    final r = reconcile(assigned: ['a', 'gone']);
    expect(r.saved, ['a']);
    expect(r.toRegister, ['a']);

    expect(reconcile(assigned: ['gone']).saved, isEmpty);
  });

  test('Danh sách chưa tải lại (cũ / lỗi mạng): không bỏ chip, vẫn đăng ký', () {
    final r = reconcile(assigned: ['gone'], fresh: false);
    expect(r.saved, ['gone']);
    expect(r.toRegister, ['gone']);
  });

  test('Vừa gán chip mà máy chưa vào danh sách: giữ đúng một nhịp', () {
    final justAssigned = reconcile(assigned: ['new'], keepIfAllMissing: true);
    expect(justAssigned.saved, ['new']);
    expect(justAssigned.toRegister, ['new']);

    // Nhịp tim sau: tải lại vẫn không thấy → máy đã xóa thật.
    expect(reconcile(assigned: ['new']).saved, isEmpty);
  });

  test('Chưa tải được danh sách cửa hàng: giữ nguyên', () {
    final r = reconcile(assigned: ['a'], store: const [], active: const []);
    expect(r.saved, ['a']);
    expect(r.toRegister, ['a']);
  });

  test('Chưa chọn chip: rỗng', () {
    final r = reconcile(assigned: const []);
    expect(r.saved, isEmpty);
    expect(r.toRegister, isEmpty);
  });
}
