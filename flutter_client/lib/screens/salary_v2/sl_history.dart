import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'sl_common.dart';
import 'sl_model.dart';

/// Một dòng trong lịch sử lương: phiên bản theo ngày hiệu lực, hoặc đính chính / bản bị thay / thay đổi bị hủy.
class SalaryLogEntry {
  SalaryLogEntry({
    required this.kind,
    required this.sortAt,
    required this.benefit,
    this.after,
    this.from,
    this.to,
    this.at,
    this.by,
    this.versionId,
  });

  /// version / correction / replaced / cancelled
  final String kind;
  final DateTime sortAt;
  final Map<String, dynamic> benefit;
  final Map<String, dynamic>? after;
  final DateTime? from;
  final DateTime? to;
  final DateTime? at;
  final String? by;
  final String? versionId;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

/// Gộp phiên bản + các lần đổi (mới nhất trước). [data] = SalaryLogDto (versions, changes).
List<SalaryLogEntry> parseSalaryLog(Map<String, dynamic> data) {
  final out = <SalaryLogEntry>[];
  for (final v in (data['versions'] as List? ?? const [])) {
    final m = _map(v);
    final from = _date(m['from']);
    final eff = _date(m['effectiveDate']);
    out.add(SalaryLogEntry(
      kind: 'version',
      sortAt: eff ?? from ?? DateTime(1900),
      benefit: _map(m['benefit']),
      from: from,
      to: _date(m['to']),
      versionId: m['id']?.toString(),
    ));
  }
  for (final c in (data['changes'] as List? ?? const [])) {
    final m = _map(c);
    final at = parseApiUtcDateTime(m['at'])?.toLocal();
    out.add(SalaryLogEntry(
      kind: '${m['kind'] ?? 'correction'}',
      sortAt: at ?? DateTime(1900),
      benefit: _map(m['before']),
      after: m['after'] is Map ? _map(m['after']) : null,
      from: _date(m['effectiveDate']),
      to: _date(m['endDate']),
      at: at,
      by: m['by']?.toString(),
      versionId: m['versionId']?.toString(),
    ));
  }
  out.sort((a, b) => b.sortAt.compareTo(a.sortAt));
  return out;
}

/// Các thay đổi chính giữa hai hồ sơ lương: «Lương cơ bản: 8.000.000đ → 9.000.000đ».
List<String> salaryDiff(Map<String, dynamic> before, Map<String, dynamic> after) {
  final a = SalaryDraft.fromBenefit(before);
  final b = SalaryDraft.fromBenefit(after);
  final out = <String>[];
  void num2(String label, num x, num y, {bool isMoney = true}) {
    if ((x - y).abs() < 0.5) return;
    String f(num v) => isMoney ? money(v) : (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1));
    out.add('$label: ${f(x)} → ${f(y)}');
  }

  if (a.kind != b.kind) out.add('Loại lương: ${a.kind.label} → ${b.kind.label}');
  if (a.kind == SalaryKind.hourly || b.kind == SalaryKind.hourly) {
    num2('Lương giờ', a.base, b.base);
  } else {
    num2('Lương cơ bản', a.base, b.base);
  }
  num2('Lương hoàn thành', a.completion, b.completion);
  num2('Lương ngày', a.daily, b.daily);
  num2('Lương mỗi ca', a.perShift, b.perShift);
  if (a.shiftType != b.shiftType) {
    out.add('Lương ca: ${a.shiftType == 1 ? 'theo bậc' : 'cố định'} → ${b.shiftType == 1 ? 'theo bậc' : 'cố định'}');
  }
  if (a.insurance != b.insurance) out.add('Bảo hiểm: ${a.insurance.label} → ${b.insurance.label}');
  num2('Mức đóng BHXH', a.insuranceCustom, b.insuranceCustom);
  num2('Công chuẩn', a.stdDays, b.stdDays, isMoney: false);
  num2('Giờ / ngày', a.hoursPerDay, b.hoursPerDay, isMoney: false);
  num2('Phép năm (ngày)', a.paidLeaveDays, b.paidLeaveDays, isMoney: false);
  if (a.hourlyOtType != b.hourlyOtType) out.add('Cách tính tăng ca giờ đã đổi');
  num2('Tăng ca giờ cố định', a.hourlyOtFixed, b.hourlyOtFixed);
  if (a.holidayOtType != b.holidayOtType) out.add('Cách tính làm ngày lễ đã đổi');
  num2('Làm ngày lễ cố định', a.holidayOtDaily, b.holidayOtDaily);
  const allowances = {
    'mealAllowance': 'Phụ cấp ăn',
    'transportAllowance': 'Phụ cấp đi lại',
    'housingAllowance': 'Phụ cấp nhà ở',
    'responsibilityAllowance': 'Phụ cấp trách nhiệm',
    'attendanceBonus': 'Thưởng chuyên cần',
    'phoneSkillShiftAllowance': 'Phụ cấp điện thoại / ca',
  };
  allowances.forEach((k, label) {
    final x = (before[k] as num?) ?? 0;
    final y = (after[k] as num?) ?? 0;
    num2(label, x, y);
  });
  return out;
}

String salaryAmountText(Map<String, dynamic> benefit) {
  final d = SalaryDraft.fromBenefit(benefit);
  return d.kind == SalaryKind.shift && d.shiftType == 1 ? 'Lương ca theo bậc' : '${money(d.mainRate)}${d.kind.unit}';
}

String _dmyHm(DateTime d) =>
    '${dmy(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Bảng lịch sử lương của nhân viên. [onCancelUpcoming] trả true khi đã hủy (đóng màn sửa).
Future<void> showSalaryHistorySheet(
  BuildContext context, {
  required SlContext ctx,
  required SlEmployee employee,
  required bool canEdit,
  required Future<void> Function(String versionId) onCancelUpcoming,
}) async {
  final res = await ctx.api.getSalaryLog(employee.id);
  List<SalaryLogEntry> entries;
  var ok = res['isSuccess'] == true && res['data'] is Map;
  if (ok) {
    entries = parseSalaryLog(Map<String, dynamic>.from(res['data'] as Map));
  } else {
    // Máy chủ cũ chưa có salary-log → chỉ các phiên bản.
    final old = await ctx.api.getSalaryHistory(employee.id);
    ok = old['isSuccess'] == true;
    entries = parseSalaryLog({'versions': old['data'] is List ? old['data'] : const []});
  }
  if (!context.mounted) return;
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(tr('Lịch sử thay đổi lương — ${employee.name}'), style: SboxType.titleStyle()),
          const SizedBox(height: 4),
          Text(
            tr('Gồm các lần đổi lương theo ngày, các lần đính chính và bản bị thay. Không có lần nào bị mất khi sửa.'),
            style: SboxType.captionStyle(),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(tr(ok ? 'Chưa có thay đổi nào.' : 'Không tải được lịch sử.'), style: SboxType.smallStyle()),
          for (final e in entries) _entryTile(sheetCtx, e, todayDate, canEdit, onCancelUpcoming),
        ]),
      ),
    ),
  );
}

Widget _entryTile(
  BuildContext ctx,
  SalaryLogEntry e,
  DateTime today,
  bool canEdit,
  Future<void> Function(String versionId) onCancelUpcoming,
) {
  final amount = salaryAmountText(e.benefit);
  final kindLabel = SalaryDraft.fromBenefit(e.benefit).kind.label;
  String range(DateTime? from, DateTime? to) => [
        from == null || from.year < 1900 ? 'Từ đầu' : 'Từ ${dmy(from)}',
        if (to != null && to.year < 9000) 'đến ${dmy(to)}' else 'đến nay',
      ].join(' ');
  final who = [if (e.at != null) _dmyHm(e.at!), if ((e.by ?? '').isNotEmpty) e.by!].join(' · ');

  switch (e.kind) {
    case 'version':
      final future = e.from != null && e.from!.isAfter(today) && e.from!.year > 1900;
      final current = !future && (e.to == null || e.to!.year > 9000 || !e.to!.isBefore(today));
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          future ? Icons.schedule_rounded : (current ? Icons.check_circle_rounded : Icons.history_rounded),
          color: future ? SboxColors.warning : (current ? SboxColors.success : SboxColors.slate500),
        ),
        title: Text('$amount · $kindLabel'),
        subtitle: Text(tr([
          range(e.from, e.to),
          if (future) 'sắp áp dụng',
          if (current) 'đang áp dụng',
        ].join(' · '))),
        onTap: () => _showProfile(ctx, tr('Hồ sơ lương ${range(e.from, e.to)}'), e.benefit),
        trailing: future && canEdit && e.versionId != null
            ? TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onCancelUpcoming(e.versionId!);
                },
                child: Text(tr('Hủy thay đổi')),
              )
            : null,
      );
    case 'correction':
      final diff = e.after == null ? <String>[] : salaryDiff(e.benefit, e.after!);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.edit_note_rounded, color: SboxColors.brand700),
        title: Text(tr('Đính chính hồ sơ${e.from != null && e.from!.year > 1900 ? ' (áp dụng từ ${dmy(e.from!)})' : ''}')),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (who.isNotEmpty) Text(who, style: SboxType.captionStyle()),
          for (final d in diff.isEmpty ? [tr('Đổi thiết lập khác (không đổi mức lương)')] : diff)
            Text('• ${tr(d)}', style: SboxType.smallStyle()),
        ]),
        onTap: () => _showProfile(ctx, tr('Hồ sơ trước khi đính chính'), e.benefit),
      );
    case 'replaced':
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.swap_horiz_rounded, color: SboxColors.warning),
        title: Text(tr('Bản bị thay: $amount · $kindLabel')),
        subtitle: Text(tr([
          'Đang áp dụng ${range(e.from, e.to).toLowerCase()} thì được thay bằng mức mới',
          if (who.isNotEmpty) who,
        ].join(' · '))),
        onTap: () => _showProfile(ctx, tr('Hồ sơ bị thay'), e.benefit),
      );
    default: // cancelled
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cancel_outlined, color: SboxColors.slate500),
        title: Text(tr('Đã hủy thay đổi: $amount · $kindLabel')),
        subtitle: Text(tr([
          if (e.from != null) 'Dự kiến áp dụng từ ${dmy(e.from!)}',
          if (who.isNotEmpty) who,
        ].join(' · '))),
        onTap: () => _showProfile(ctx, tr('Thay đổi đã hủy'), e.benefit),
      );
  }
}

/// Xem nhanh toàn bộ hồ sơ lương tại một thời điểm.
Future<void> _showProfile(BuildContext context, String title, Map<String, dynamic> b) {
  final d = SalaryDraft.fromBenefit(b);
  String n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  final rows = <(String, String)>[
    ('Loại lương', d.kind.label),
    if (d.kind == SalaryKind.monthly) ...[
      ('Lương cơ bản', money(d.base)),
      ('Lương hoàn thành', money(d.completion)),
    ],
    if (d.kind == SalaryKind.hourly) ('Lương giờ', money(d.base)),
    if (d.kind == SalaryKind.daily) ('Lương ngày', money(d.daily)),
    if (d.kind == SalaryKind.shift) ('Lương ca', d.shiftType == 1 ? 'Theo bậc' : money(d.perShift)),
    ('Bảo hiểm', d.insurance.label),
    ('Công chuẩn', d.fixedStdDays ? '${d.stdDays} ngày (cố định)' : '${d.stdDays} ngày'),
    ('Giờ / ngày', n(d.hoursPerDay)),
    ('Phép năm', '${d.paidLeaveDays} ngày'),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(tr(r.$1), style: SboxType.smallStyle())),
                Text(r.$2, style: SboxType.bodyStrong()),
              ]),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
    ),
  );
}
