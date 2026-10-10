/// Chương trình tính lương chạy trên máy chủ (API C# gọi khi xem / chốt bảng lương).
///
/// Đầu vào (stdin, JSON — token không đưa lên dòng lệnh để khỏi lộ qua danh sách tiến trình):
///   {"baseUrl": "http://127.0.0.1:7070", "token": "...", "from": "2026-08-01", "to": "2026-08-31",
///    "employeeRole": false, "branchId": null, "headquarterId": null, "withSnapshots": false,
///    "finalize": false, "employeeIds": null, "branchHeader": null}
/// finalize=true: thêm "finalize": {request: {year, month, periodStart, periodEnd, items}, skipped: [...]}
///   — yêu cầu chốt lương dựng từ số máy chủ tự tính (employeeIds rỗng = mọi NV trong bảng).
/// Đầu ra (stdout, JSON): {"ok": true, "rows": [...], "notConfiguredSalaryCount": n,
///    "snapshots": {"<mã NV>": {...}}, "requests": n, "elapsedMs": n}
library;

import 'dart:convert';
import 'dart:io';

import 'package:payroll_engine/http_payroll_api.dart';
import 'package:payroll_engine/payroll/payroll_engine.dart';
import 'package:payroll_engine/payroll/payroll_finalize.dart';

DateTime _day(String s) {
  final d = DateTime.parse(s);
  return DateTime(d.year, d.month, d.day);
}

/// Như BranchFilterHelper.branchMatches của app: NV chưa gán chi nhánh thuộc trụ sở.
bool _inBranch(String? itemBranchId, String? selected, String? headquarterId) {
  if (selected == null || selected.isEmpty) return true;
  final bid = itemBranchId?.trim();
  if (bid == null || bid.isEmpty || bid == 'null') {
    return headquarterId == null || headquarterId.isEmpty || headquarterId == selected;
  }
  return bid == selected;
}

Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();
  HttpPayrollApi? api;
  try {
    final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map<String, dynamic>;
    api = HttpPayrollApi(
      baseUrl: input['baseUrl'] as String,
      token: input['token'] as String,
      branchHeader: input['branchHeader'] as String?,
    );
    final engine = PayrollEngine(api: api, isEmployeeRole: input['employeeRole'] == true)
      ..fromDate = _day(input['from'] as String)
      ..toDate = _day(input['to'] as String);
    await engine.loadPayrollData();

    final branchId = input['branchId'] as String?;
    final hq = input['headquarterId'] as String?;
    final rows = engine.computeRows(
      includeEmployee: branchId == null || branchId.isEmpty ? null : (e) => _inBranch(e.branchId, branchId, hq),
    )..sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));

    final snapshots = <String, dynamic>{};
    if (input['withSnapshots'] == true) {
      for (final r in rows) {
        final code = '${r['code']}';
        snapshots[code] = engine.buildAttendanceSnapshot(code, r);
      }
    }

    Map<String, dynamic>? finalize;
    if (input['finalize'] == true) {
      final ids = (input['employeeIds'] as List?)?.map((e) => '$e'.toLowerCase()).toSet() ?? const <String>{};
      final pick = ids.isEmpty
          ? rows
          : rows.where((r) => ids.contains('${r['employeeId']}'.toLowerCase()) || ids.contains('${r['code']}'.toLowerCase())).toList();
      final batch = buildPayrollFinalizeBatch(engine, pick);
      finalize = {'request': batch.request, 'skipped': batch.skipped};
    }

    stdout.write(jsonEncode({
      'ok': true,
      'rows': rows,
      'notConfiguredSalaryCount': engine.notConfiguredSalaryCount,
      'warnings': engine.configWarnings(),
      if (snapshots.isNotEmpty) 'snapshots': snapshots,
      if (finalize != null) 'finalize': finalize,
      'requests': api.requestCount,
      'elapsedMs': sw.elapsedMilliseconds,
    }, toEncodable: (o) => o is DateTime ? o.toIso8601String() : o.toString()));
    await stdout.flush();
    api.close();
    exit(0);
  } catch (e, st) {
    stdout.write(jsonEncode({'ok': false, 'error': '$e', 'stack': '$st'.split('\n').take(8).join('\n')}));
    await stdout.flush();
    api?.close();
    exit(1);
  }
}
