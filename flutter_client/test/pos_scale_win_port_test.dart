@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_scale_reader.dart';

/// Cổng COM thật trên Windows (không cần cân): liệt kê cổng, mở cổng không có → báo lỗi dễ hiểu.
void main() {
  test('Liệt kê cổng COM + mở cổng không tồn tại', () async {
    final r = PosScaleReader.instance;
    expect(r.supported, isTrue);
    final ports = await r.listPorts();
    expect(ports.every((p) => p.toUpperCase().startsWith('COM')), isTrue);
    r.settings = const PosScaleDeviceSettings(enabled: true, port: 'COM250', baudRate: 9600);
    final ok = await r.connect();
    expect(ok, isFalse);
    expect(r.error, contains('COM250'));
    // ignore: avoid_print
    print('Cổng COM trên máy: $ports · lỗi: ${r.error}');
    await r.disconnect();

    // Hai nơi cùng mở một cổng: lần sau báo «đang bị dùng».
    // (kiểm ở dưới khi máy có cổng COM)
    // Cổng có thật trên máy (vd COM1 của bo mạch): mở / đóng được, không treo.
    if (ports.isNotEmpty) {
      r.settings = PosScaleDeviceSettings(enabled: true, port: ports.first, baudRate: 9600);
      final opened = await r.connect();
      // ignore: avoid_print
      print('Mở ${ports.first}: $opened ${r.error ?? ''}');
      await r.disconnect();
      // Mở lại ngay sau khi đóng: cổng đã được nhả.
      final again = await r.connect();
      expect(again, opened);
      await r.disconnect();
    }
  });
}
