// Chạy với máy in giả: python -I scripts/qa/fake_udp_printer.py
// rồi: SBOX_FAKE_UDP_PRINTER=1 flutter test test/pos_lan_printer_netconfig_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_lan_printer_netconfig.dart';

void main() {
  final live = Platform.environment['SBOX_FAKE_UDP_PRINTER'] == '1';

  test('dò broadcast thấy 3 họ, SAVE đổi IP máy Xprinter giả', () async {
    var list = await PosLanNetConfig.discover();
    final protos = list.map((d) => d.proto).toSet();
    expect(protos, containsAll(PosLanNetProto.values));
    final xp = list.firstWhere((d) => d.proto == PosLanNetProto.xprinter);
    expect(xp.ip, '192.168.123.100');
    expect(xp.macText, '00:11:22:33:44:55');

    await PosLanNetConfig.sendStaticIp(xp,
        ip: '192.168.1.222', mask: '255.255.255.0', gateway: '192.168.1.1');
    list = await PosLanNetConfig.discover();
    expect(list.firstWhere((d) => d.key == xp.key).ip, '192.168.1.222');
  }, skip: live ? false : 'cần SBOX_FAKE_UDP_PRINTER=1 + scripts/qa/fake_udp_printer.py');
}
