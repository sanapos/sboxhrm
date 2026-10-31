import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_printer_transport.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';

/// Máy in LAN nhận lệnh nhưng giữ kết nối (không đóng chiều kia) — trước đây lệnh in LAN chờ
/// `socket.close()` mãi: phiếu bếp đứng không báo gì, mọi lần in sau tới máy đó xếp hàng sau nó (C20 → LAN .89).
void main() {
  test('In LAN xong dù máy in giữ kết nối; lần in sau cùng máy không bị chặn', () async {
    final received = <int>[];
    final held = <Socket>[];
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      held.add(s);
      s.listen(received.addAll, onError: (_) {});
    });
    addTearDown(() async {
      for (final s in held) {
        s.destroy();
      }
      await server.close();
    });

    Future<bool> send(List<int> bytes) => PosPrinterTransport.send(
          connectionType: PosThermalConnectionType.lan,
          lanHost: '127.0.0.1',
          lanPort: server.port,
          bytes: bytes,
        ).timeout(const Duration(seconds: 8));

    expect(await send(const [0x1B, 0x40, 0x41, 0x0A]), isTrue);
    expect(await send(const [0x1B, 0x40, 0x42, 0x0A]), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, containsAllInOrder(const [0x41, 0x0A, 0x42, 0x0A]));
  });
}
