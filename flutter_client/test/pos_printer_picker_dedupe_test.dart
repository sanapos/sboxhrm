import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_store_printer.dart';
import 'package:zkteco_flutter_client/utils/pos_print_orchestrator.dart';

PosStorePrinter _lan(String id, String name, {String? brand, bool local = true}) => PosStorePrinter(
      id: id,
      name: name,
      connectionType: 'Lan',
      printerBrand: brand,
      lanHost: '127.0.0.1',
      isDeviceLocal: local,
      ownerDeviceId: local ? 'dev-1' : null,
    );

void main() {
  test('Máy tem và máy nhiệt cùng IP:cổng vẫn là hai máy trong bảng chọn', () {
    final list = PosPrintOrchestrator.uniquePrintersForPicker(
      [_lan('a', 'LAN 127.0.0.1', brand: 'label'), _lan('b', 'Máy in nhiệt nội bộ', brand: 'zywell')],
      deviceId: 'dev-1',
    );
    expect(list.map((p) => p.id).toSet(), {'a', 'b'});
  });

  test('Bản sao Cloud + nội bộ của cùng máy nhiệt vẫn gộp làm một', () {
    final list = PosPrintOrchestrator.uniquePrintersForPicker(
      [_lan('a', 'Máy HĐ', brand: 'zywell'), _lan('b', 'Máy HĐ', brand: 'zywell', local: false)],
      deviceId: 'dev-1',
    );
    expect(list.map((p) => p.id), ['b']);
  });
}
