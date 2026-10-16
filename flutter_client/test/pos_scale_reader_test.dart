import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_scale_reader.dart';

/// Dữ liệu cân điện tử qua cổng COM / Web Serial → kg.
void main() {
  PosScaleReading? one(String s, {String unit = 'kg'}) => PosScaleFrameParser.parseLine(s, unitWhenMissing: unit);

  test('Khung CAS / A&D: ST ổn định, US đang dao động', () {
    final st = one('ST,GS,+  0.456kg')!;
    expect((st.kg, st.stable), (0.456, true));
    final us = one('US,GS,+  1.250kg')!;
    expect((us.kg, us.stable), (1.25, false));
    expect(one('ST,NT,-  0.020kg')!.kg, -0.02);
  });

  test('Đơn vị g / lb / không đơn vị', () {
    expect(one('   456 g')!.kg, 0.456);
    expect(one('2.000 lb')!.kg, closeTo(0.907, 0.001));
    expect(one('  0.75')!.kg, 0.75);
    expect(one('  750', unit: 'g')!.kg, 0.75);
    expect(one('OL'), isNull);
    expect(one(''), isNull);
  });

  test('Yaohua XK3190 «=» số đảo ngược', () {
    expect(one('=654.0000')!.kg, 0.456);
  });

  test('Tách khung theo CR/LF và «=» liên tục', () {
    final p = PosScaleFrameParser();
    final a = p.feed(ascii.encode('ST,GS,+  0.4'));
    expect(a, isEmpty);
    final b = p.feed(ascii.encode('56kg\r\nST,GS,+  0.457kg\r\n'));
    expect(b.map((r) => r.kg), [0.456, 0.457]);
    final y = PosScaleFrameParser();
    final r = y.feed(ascii.encode('=654.0000=654.0000'));
    expect(r.map((x) => x.kg), [0.456, 0.456]);
  });
}
