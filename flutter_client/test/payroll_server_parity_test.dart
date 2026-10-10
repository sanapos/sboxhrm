import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_engine/http_payroll_api.dart';
import 'package:payroll_engine/payroll/payroll_engine.dart';

import 'fixtures/payroll_fixture.dart';

/// Đường chạy MÁY CHỦ (chương trình payroll_engine): tự nạp dữ liệu qua HTTP như API thật,
/// tính bảng lương → phải ra đúng «đáp án chuẩn» của bảng lương trên app.
Future<HttpServer> _serve({
  required bool serverAdjustments,
  required List<String> seen,
  String dayEnd = '04:00',
  String nightShiftType = 'Qua đêm',
  bool lawPolicy = false,
}) async {
  final responses = payrollFixtureResponses(serverAdjustments: serverAdjustments, lawPolicy: lawPolicy)
    ..['/api/settings/app/day_end_time'] = {'key': 'day_end_time', 'value': dayEnd};
  responses['/api/shifts/templates'] = [
    for (final t in (responses['/api/shifts/templates'] as List).cast<Map<String, dynamic>>())
      t['id'] == 's2' ? {...t, 'shiftType': nightShiftType} : t,
  ];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final p = req.uri.path;
    seen.add('${req.method} $p');
    Object? body;
    var status = 200;
    if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer test-token') {
      status = 401;
    } else if (p == '/api/employees') {
      final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
      body = {'isSuccess': true, 'data': {'items': page == 1 ? payrollFixtureEmployees : [], 'totalCount': payrollFixtureEmployees.length}};
    } else if (p == '/api/devices') {
      body = {'isSuccess': true, 'data': [{'id': 'dev1', 'name': 'Máy cửa'}]};
    } else if (p == '/api/attendances/devices' && req.method == 'POST') {
      final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
      final items = payrollFixtureAttendanceJson();
      body = {'isSuccess': true, 'data': {'items': page == 1 ? items : [], 'totalCount': items.length}};
    } else {
      final hit = responses.entries.where((e) => p == e.key).firstOrNull;
      if (hit == null) {
        body = p.startsWith('/api/benefits/me') ? {'isSuccess': true, 'data': null} : {'isSuccess': true, 'data': []};
      } else if (hit.value == null) {
        status = 404;
        body = {};
      } else {
        body = {'isSuccess': true, 'data': hit.value};
      }
    }
    await req.drain<void>();
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return server;
}

/// Dùng cho test thăm dò.
Future<HttpServer> serveForProbe(List<String> seen, {String dayEnd = '04:00'}) => _serve(serverAdjustments: false, seen: seen, dayEnd: dayEnd);

List<Map<String, dynamic>> _normalize(List<Map<String, dynamic>> rows) {
  final list = (jsonDecode(jsonEncode(rows)) as List).cast<Map<String, dynamic>>();
  list.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
  return list;
}

void _expectSame(List<Map<String, dynamic>> actual, List<Map<String, dynamic>> expected) {
  expect(actual.length, expected.length, reason: 'số dòng');
  void cmp(Object? a, Object? e, String path) {
    if (e is num && a is num) {
      expect((a - e).abs() < 0.001, isTrue, reason: '$path: $a ≠ $e');
    } else if (e is Map && a is Map) {
      expect(a.keys.toSet(), e.keys.toSet(), reason: '$path: khóa');
      for (final k in e.keys) {
        cmp(a[k], e[k], '$path.$k');
      }
    } else if (e is List && a is List) {
      expect(a.length, e.length, reason: '$path: độ dài');
      for (var i = 0; i < e.length; i++) {
        cmp(a[i], e[i], '$path[$i]');
      }
    } else {
      expect(a, e, reason: path);
    }
  }

  for (var i = 0; i < expected.length; i++) {
    cmp(actual[i], expected[i], '${expected[i]['code']}');
  }
}

Future<void> _check(String golden, {required bool serverAdjustments, bool lawPolicy = false}) async {
  final seen = <String>[];
  final server = await _serve(serverAdjustments: serverAdjustments, seen: seen, lawPolicy: lawPolicy);
  final api = HttpPayrollApi(baseUrl: 'http://127.0.0.1:${server.port}', token: 'test-token');
  try {
    final engine = PayrollEngine(api: api)
      ..fromDate = DateTime(2026, 8, 1)
      ..toDate = DateTime(2026, 8, 31);
    await engine.loadPayrollData();
    final rows = _normalize(engine.computeRows());
    final expected = (jsonDecode(File('test/goldens/$golden.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    _expectSame(rows, expected);
    expect(seen, contains('POST /api/attendances/devices'), reason: 'máy chủ tự tải chấm công');
    expect(engine.notConfiguredSalaryCount, 1, reason: 'NV005 chưa có bảng lương');
  } finally {
    api.close();
    await server.close(force: true);
  }
}

/// Chạy đúng file thực thi đã biên dịch (như trên máy chủ): stdin JSON → stdout JSON.
Future<void> _checkExe() async {
  final exe = File('../src/payroll_engine/build/payroll_engine${Platform.isWindows ? '.exe' : ''}');
  if (!exe.existsSync()) {
    markTestSkipped('chưa biên dịch payroll_engine');
    return;
  }
  final seen = <String>[];
  final server = await _serve(serverAdjustments: false, seen: seen);
  try {
    final proc = await Process.start(exe.path, const [], environment: {'TZ': 'Asia/Ho_Chi_Minh'});
    proc.stdin.write(jsonEncode({
      'baseUrl': 'http://127.0.0.1:${server.port}',
      'token': 'test-token',
      'from': '2026-08-01',
      'to': '2026-08-31',
      'finalize': true,
    }));
    await proc.stdin.close();
    final out = await proc.stdout.transform(utf8.decoder).join();
    expect(await proc.exitCode, 0, reason: out);
    final res = jsonDecode(out) as Map<String, dynamic>;
    expect(res['ok'], isTrue);
    final rows = _normalize((res['rows'] as List).cast<Map<String, dynamic>>());
    final expected = (jsonDecode(File('test/goldens/payroll_rows_local.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    _expectSame(rows, expected);
    final fin = res['finalize'] as Map<String, dynamic>;
    // NV005 chưa có bảng lương → bỏ qua; còn lại có phiếu.
    expect((fin['request']['items'] as List).length, 6);
    expect(fin['skipped'], hasLength(1));
    final nv1 = (fin['request']['items'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['employeeId'] == 'e1');
    final row1 = rows.firstWhere((r) => r['code'] == 'NV001');
    expect((nv1['netSalary'] as num) - (row1['netSalary'] as num), 0);
  } finally {
    await server.close(force: true);
  }
}

Future<({List<String> warnings, Map<String, dynamic> nv4})> _night(String dayEnd, {String nightShiftType = 'Qua đêm'}) async {
  final server = await _serve(serverAdjustments: false, seen: [], dayEnd: dayEnd, nightShiftType: nightShiftType);
  final api = HttpPayrollApi(baseUrl: 'http://127.0.0.1:${server.port}', token: 'test-token');
  try {
    final engine = PayrollEngine(api: api)
      ..fromDate = DateTime(2026, 8, 1)
      ..toDate = DateTime(2026, 8, 31);
    await engine.loadPayrollData();
    final nv4 = engine.computeRows().firstWhere((r) => r['code'] == 'NV004');
    return (warnings: engine.configWarnings(), nv4: nv4);
  } finally {
    api.close();
    await server.close(force: true);
  }
}

void main() {
  test('Ca đêm 22:00–06:00 đủ công dù giờ chốt ngày 00:00 / 04:00 / 07:00', () async {
    for (final de in ['00:00', '04:00', '07:00']) {
      final r = await _night(de);
      expect(r.nv4['totalShifts'], 15, reason: 'giờ chốt $de');
      expect(r.warnings, isEmpty, reason: 'giờ chốt $de');
    }
  });

  test('Ca qua nửa đêm nhưng loại ca không phải «Qua đêm» → cảnh báo', () async {
    final r = await _night('04:00', nightShiftType: 'Hành chính');
    expect(r.warnings, hasLength(1));
    expect(r.warnings.first, contains('Qua đêm'));
  });

  test('Chương trình payroll_engine (file thực thi) ra đúng bảng lương + phiếu chốt', _checkExe);

  test('Máy chủ ra đúng bảng lương như app — khoản cộng / trừ tính trên máy', () async {
    await _check('payroll_rows_local', serverAdjustments: false);
  });

  test('Máy chủ ra đúng bảng lương như app — chính sách «Theo luật»', () async {
    await _check('payroll_rows_law', serverAdjustments: false, lawPolicy: true);
  });

  test('Máy chủ ra đúng bảng lương như app — khoản cộng / trừ do máy chủ tính sẵn', () async {
    await _check('payroll_rows_server_adj', serverAdjustments: true);
  });
}
