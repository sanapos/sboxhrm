import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/utils/pos_lan_printer_netconfig.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    s.split(' ').where((e) => e.isNotEmpty).map((e) => int.parse(e, radix: 16)).toList());

final _mac = Uint8List.fromList(const [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);

void main() {
  group('gói dò', () {
    test('Xprinter / Rongta / Epson FIND đúng byte SDK', () {
      expect(PosLanNetCodec.xpFind, _hex('58 50 30 30 30 31 46 49 4E 44'));
      expect(PosLanNetCodec.rtFind, _hex('4D 50 34 32 30 30 46 49 4E 44'));
      expect(PosLanNetCodec.epsonProbe, _hex('45 50 53 4F 4E 50 00 FF 00 00 00 00 00 00 00'));
    });
  });

  group('SAVE (đặt IP tĩnh)', () {
    test('Xprinter: ví dụ 192.168.1.200/24 gw .1', () {
      final p = PosLanNetCodec.save(PosLanNetProto.xprinter,
          mac: _mac, ip: '192.168.1.200', mask: '255.255.255.0', gateway: '192.168.1.1');
      expect(
          p,
          _hex('58 50 30 30 30 31 53 41 56 45 00 11 22 33 44 55 22 00 '
              'C0 A8 01 C8 FF FF FF 00 C0 A8 01 01 8C 17 00'));
      expect(p.length, 33);
    });

    test('Rongta: hằng 0F 00 / 05 B4 riêng', () {
      final p = PosLanNetCodec.save(PosLanNetProto.rongta,
          mac: _mac, ip: '10.0.0.50', mask: '255.255.0.0', gateway: '10.0.0.1');
      expect(
          p,
          _hex('4D 50 34 32 30 30 53 41 56 45 00 11 22 33 44 55 0F 00 '
              '0A 00 00 32 FF FF 00 00 0A 00 00 01 05 B4 00'));
    });

    test('Epson không có gói SAVE; MAC / IP sai thì báo lỗi', () {
      expect(
          () => PosLanNetCodec.save(PosLanNetProto.epson,
              mac: _mac, ip: '1.2.3.4', mask: '255.0.0.0', gateway: '1.0.0.1'),
          throwsUnsupportedError);
      expect(
          () => PosLanNetCodec.save(PosLanNetProto.xprinter,
              mac: Uint8List(5), ip: '1.2.3.4', mask: '255.0.0.0', gateway: '1.0.0.1'),
          throwsArgumentError);
      expect(
          () => PosLanNetCodec.save(PosLanNetProto.xprinter,
              mac: _mac, ip: '1.2.3.256', mask: '255.0.0.0', gateway: '1.0.0.1'),
          throwsArgumentError);
    });
  });

  group('đọc trả lời', () {
    test('Xprinter FOUND: MAC 11, IP 19, mask 23, gw 27, DHCP 33', () {
      final d = PosLanNetCodec.parse(
          _hex('58 50 30 30 30 31 46 4F 55 4E 44 00 11 22 33 44 55 AA BB '
              'C0 A8 7B 64 FF FF FF 00 C0 A8 7B 01 CC DD 00'),
          '192.168.123.100')!;
      expect(d.proto, PosLanNetProto.xprinter);
      expect(d.macText, '00:11:22:33:44:55');
      expect(d.ip, '192.168.123.100');
      expect(d.mask, '255.255.255.0');
      expect(d.gateway, '192.168.123.1');
      expect(d.dhcp, false);
      expect(d.canSetIp, true);
    });

    test('Xprinter FOUND ngắn (< 34 byte) bị bỏ', () {
      expect(PosLanNetCodec.parse(_hex('58 50 30 30 30 31 46 4F 55 4E 44 00 11'), '1.1.1.1'),
          isNull);
    });

    test('Rongta/Zywell FOUND thật (ZY80-Q2, 64 byte)', () {
      final d = PosLanNetCodec.parse(
          _hex('4d 50 34 32 30 30 46 4f 55 4e 44 00 60 35 d1 f3 82 3c 00 c0 a8 01 59 ff ff ff 00 '
              'c0 a8 01 01 8c 23 00 5a 59 38 30 2d 51 32 00 00 00 00 00 00 00 00 00 00 00 00 00 '
              '00 00 00 00 00 00 01 13 00 00 00'),
          '192.168.1.89')!;
      expect(d.proto, PosLanNetProto.rongta);
      expect(d.macText, '00:60:35:D1:F3:82');
      expect(d.ip, '192.168.1.89');
      expect(d.mask, '255.255.255.0');
      expect(d.gateway, '192.168.1.1');
      expect(d.dhcp, false);
      expect(d.model, 'ZY80-Q2');
      // Gói SAVE thật đã gửi (.89 → .201) — giữ 3C 00 / 8C 23 của máy, không dùng hằng SDK.
      expect(
          PosLanNetCodec.save(d.proto,
              mac: d.mac!,
              ip: '192.168.1.201',
              mask: '255.255.255.0',
              gateway: '192.168.1.1',
              keep17: d.keep17,
              keep31: d.keep31),
          _hex('4d 50 34 32 30 30 53 41 56 45 00 60 35 d1 f3 82 3c 00 c0 a8 01 c9 ff ff ff 00 '
              'c0 a8 01 01 8c 23 00'));
    });

    test('model rác sau khi đổi IP (gói thật) → null', () {
      final raw = _hex('4d 50 34 32 30 30 46 4f 55 4e 44 00 60 35 d1 f3 82 3c 00 c0 a8 01 c9 ff ff ff 00 '
          'c0 a8 01 01 8c 23 00 8e c1 51 f7 31 36 38 03 31 39 32 07 69 6e 2d 61 00');
      expect(PosLanNetCodec.parse(raw, '192.168.1.201')!.model, isNull);
    });

    test('Rongta FOUND không có IP trong gói: lấy IP nguồn, DHCP [33] != 0', () {
      final raw = Uint8List(40)..setAll(0, 'MP4200FOUND'.codeUnits);
      raw.setAll(11, _mac);
      raw[33] = 2;
      final d = PosLanNetCodec.parse(raw, '192.168.123.100')!;
      expect(d.proto, PosLanNetProto.rongta);
      expect(d.ip, '192.168.123.100');
      expect(d.dhcp, true);
      expect(d.mask, isNull);
    });

    test('Epson: chỉ nhận trả lời (chữ thường), bỏ gói dò của chính mình', () {
      expect(PosLanNetCodec.parse(PosLanNetCodec.epsonProbe, '192.168.1.5'), isNull);
      final reply = Uint8List.fromList([...'EPSONp'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]);
      final d = PosLanNetCodec.parse(reply, '192.168.192.168')!;
      expect(d.proto, PosLanNetProto.epson);
      expect(d.canSetIp, false);
    });

    test('gói dò FIND của chính mình / rác không bị nhận nhầm', () {
      expect(PosLanNetCodec.parse(PosLanNetCodec.xpFind, '192.168.1.5'), isNull);
      expect(PosLanNetCodec.parse(PosLanNetCodec.rtFind, '192.168.1.5'), isNull);
      expect(PosLanNetCodec.parse(Uint8List(0), '192.168.1.5'), isNull);
    });
  });

  group('IPv4', () {
    test('parse / mask / cùng lớp mạng', () {
      expect(parseIpv4('192.168.1.10'), [192, 168, 1, 10]);
      expect(parseIpv4('192.168.1'), isNull);
      expect(parseIpv4('192.168.1.x'), isNull);
      expect(prefixToMask(24), '255.255.255.0');
      expect(prefixToMask(22), '255.255.252.0');
      expect(isValidMask('255.255.255.0'), true);
      expect(isValidMask('255.255.0.255'), false);
      expect(isValidMask('255.255.255.255'), false);
      expect(sameSubnet('192.168.1.50', '192.168.1.200', '255.255.255.0'), true);
      expect(sameSubnet('192.168.123.100', '192.168.1.50', '255.255.255.0'), false);
      expect(sameSubnet('192.168.0.9', '192.168.3.1', '255.255.252.0'), true);
      expect(isUsableHost('192.168.1.0', '255.255.255.0'), false);
      expect(isUsableHost('192.168.1.255', '255.255.255.0'), false);
      expect(isUsableHost('192.168.1.200', '255.255.255.0'), true);
    });

    test('IP gợi ý: bắt đầu .200, bỏ IP máy POS / gateway / đã dùng', () {
      final c = freeIpCandidates('192.168.1.200', '255.255.255.0', '192.168.1.1',
          avoid: {'192.168.1.201'});
      expect(c.first, '192.168.1.202');
      expect(c, isNot(contains('192.168.1.200')));
      expect(c, isNot(contains('192.168.1.1')));
      expect(c, contains('192.168.1.100'));
      expect(c, isNot(contains('192.168.1.255')));
      // /25 phía trên: host .200 → .128 + 72.
      final hi = freeIpCandidates('10.0.0.130', '255.255.255.128', '10.0.0.129');
      expect(hi.every((ip) => sameSubnet(ip, '10.0.0.130', '255.255.255.128')), true);
    });
  });
}
