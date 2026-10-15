import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/cccd_qr_parser.dart';

void main() {
  const full =
      '079090001234|123456789|NGUYỄN QUỐC ANH|15031990|Nam|12 Lê Lợi, Phường Bến Nghé, Quận 1, TP Hồ Chí Minh|15032021';

  test('7 trường có CMND cũ', () {
    final p = parseCccdQr(full)!;
    expect(p['cccd'], '079090001234');
    expect(p['oldIdNumber'], '123456789');
    expect(p['fullName'], 'Nguyễn Quốc Anh');
    expect(p['dob'], DateTime(1990, 3, 15));
    expect(p['gender'], 'Nam');
    expect(p['address'], '12 Lê Lợi, Phường Bến Nghé, Quận 1, TP Hồ Chí Minh');
    expect(p['issueDateValue'], DateTime(2021, 3, 15));
  });

  test('CMND cũ để trống (vẫn đủ 7 trường)', () {
    final p = parseCccdQr('079090001234||TRẦN THỊ NGỌC HÀ|01012000|Nữ|Hà Nội|20220101')!;
    expect(p['oldIdNumber'], isNull);
    expect(p['fullName'], 'Trần Thị Ngọc Hà');
    expect(p['dob'], DateTime(2000, 1, 1));
    expect(p['gender'], 'Nữ');
  });

  test('bản 6 trường không có CMND cũ', () {
    final p = parseCccdQr('079090001234|LÊ VĂN B|05061985|Nam|Đà Nẵng|01012021')!;
    expect(p['fullName'], 'Lê Văn B');
    expect(p['dob'], DateTime(1985, 6, 5));
  });

  test('máy quét thêm xuống dòng / khoảng trắng / BOM', () {
    expect(parseCccdQr('﻿$full\r\n'), isNotNull);
    expect(parseCccdQr('  $full  ')!['cccd'], '079090001234');
  });

  test('tên có nhiều khoảng trắng liền nhau', () {
    final p = parseCccdQr('079090001234||NGUYỄN   VĂN  AN|01012000|Nam|HN|01012021')!;
    expect(p['fullName'], 'Nguyễn Văn An');
  });

  test('giới tính: không dấu / tiếng Anh / lạ', () {
    String? g(String v) => parseCccdQr('079090001234||AN|01012000|$v|HN|01012021')!['gender'] as String?;
    expect(g('Nu'), 'Nữ');
    expect(g('NỮ'), 'Nữ');
    expect(g('NAM'), 'Nam');
    expect(g('Female'), 'Nữ');
    expect(g('Khác'), isNull);
  });

  test('ngày không có thật không bị cuộn sang tháng sau', () {
    final p = parseCccdQr('079090001234||AN|31021990|Nam|HN|01012021')!;
    expect(p['dob'], isNull); // 31/02 không tồn tại
    expect(parseCccdQr('079090001234||AN|15132000|Nam|HN|01012021')!['dob'], isNull); // tháng 13
    expect(parseCccdQr('079090001234||AN|00012000|Nam|HN|01012021')!['dob'], isNull); // ngày 0
  });

  test('ngày dạng dd/MM/yyyy', () {
    final p = parseCccdQr('079090001234||AN|15/03/1990|Nam|HN|01/01/2021')!;
    expect(p['dob'], DateTime(1990, 3, 15));
    expect(p['issueDateValue'], DateTime(2021, 1, 1));
  });

  test('năm nhuận 29/02', () {
    expect(parseCccdQr('079090001234||AN|29022000|Nam|HN|01012021')!['dob'], DateTime(2000, 2, 29));
    expect(parseCccdQr('079090001234||AN|29021999|Nam|HN|01012021')!['dob'], isNull);
  });

  test('không phải QR căn cước → null', () {
    expect(parseCccdQr(''), isNull);
    expect(parseCccdQr('https://example.com'), isNull);
    expect(parseCccdQr('a|b|c|d|e'), isNull); // thiếu trường
    expect(parseCccdQr('12345678901|x|AN|01012000|Nam|HN|01012021'), isNull); // 11 số
    expect(parseCccdQr('1234567890123|x|AN|01012000|Nam|HN|01012021'), isNull); // 13 số
    expect(parseCccdQr('07909000123A||AN|01012000|Nam|HN|01012021'), isNull); // có chữ
    expect(parseCccdQr('123456789|x|AN|01012000|Nam|HN|01012021'), isNull); // CMND 9 số, không phải CCCD
  });
}
