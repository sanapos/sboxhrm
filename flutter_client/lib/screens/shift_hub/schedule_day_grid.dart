import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import 'schedule_board_data.dart';
import 'shift_hub_ui.dart';

/// Bảng xếp ca một ngày: hàng = nhân viên, cột = các ca mẫu + cột «Nghỉ».
///
/// - Chạm ô: xếp / bỏ ca đó cho nhân viên (một chạm, không mở bảng chọn).
/// - Chạm đầu cột ca: chọn nhiều nhân viên cho ca ([onShiftHeader]).
/// - Giữ ô / chạm tên: bảng chi tiết (duyệt đăng ký, xin nghỉ, xoá lịch…).
/// Ô có đăng ký chờ duyệt hoặc nghỉ phép đã duyệt: chạm mở chi tiết thay vì xếp thẳng.
class ScheduleDayGrid extends StatelessWidget {
  const ScheduleDayGrid({
    super.key,
    required this.data,
    required this.day,
    required this.compact,
    required this.busy,
    required this.onToggleShift,
    required this.onToggleDayOff,
    required this.onDetail,
    required this.onShiftHeader,
  });

  final BoardData data;
  final String day;
  final bool compact;

  /// Ô đang gửi lên máy chủ: [busyKey].
  final Set<String> busy;
  final void Function(Map<String, dynamic> emp, Map<String, dynamic> tpl) onToggleShift;
  final void Function(Map<String, dynamic> emp) onToggleDayOff;
  final void Function(Map<String, dynamic> emp) onDetail;
  final void Function(Map<String, dynamic> tpl) onShiftHeader;

  static String busyKey(dynamic empId, String day, String slot) => '$empId|$day|$slot';

  @override
  Widget build(BuildContext context) {
    final tpls = data.templates;
    final emps = data.employees;
    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 2;
      final nameW = compact ? (inner * 0.32).clamp(100.0, 170.0) : 220.0;
      final offW = compact ? 52.0 : 84.0;
      final minCol = compact ? 62.0 : 118.0;
      final avail = inner - nameW;
      final colW = tpls.isEmpty ? minCol : math.max(minCol, (avail - offW) / tpls.length);
      final gridW = math.max(avail, colW * tpls.length + offW);
      final rowH = compact ? 48.0 : 54.0;
      final headH = compact ? 66.0 : 70.0;

      Widget rowBox(Widget child, {double? h, Color? color}) => Container(
            height: h ?? rowH,
            decoration: BoxDecoration(color: color, border: const Border(top: BorderSide(color: SboxColors.slate100))),
            child: child,
          );

      final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: headH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: SboxColors.slate50,
          child: Text(tr('Nhân viên (${emps.length})'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SboxColors.slate600)),
        ),
        for (final e in emps) rowBox(_nameCell(e)),
      ]);

      final gridCol = SizedBox(
        width: gridW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: headH,
            color: SboxColors.slate50,
            child: Row(children: [
              for (final t in tpls) SizedBox(width: colW, child: _shiftHeader(t)),
              SizedBox(width: offW, child: _offHeader(emps)),
            ]),
          ),
          for (final e in emps)
            rowBox(Row(children: [
              for (final t in tpls) SizedBox(width: colW, child: _shiftCell(e, t)),
              SizedBox(width: offW, child: _offCell(e)),
            ])),
        ]),
      );

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SboxColors.slate200),
          ),
          clipBehavior: Clip.antiAlias,
          child: tpls.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Chưa có ca mẫu — vào Thiết lập → Ca mẫu để tạo ca'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                )
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: nameW, child: nameCol),
                  Container(width: 1, color: SboxColors.slate200, height: headH + emps.length * rowH),
                  Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: gridCol)),
                ]),
        ),
        if (emps.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('Không có nhân viên phù hợp'), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
          ),
        const SizedBox(height: 6),
        Text(
          tr(compact
              ? 'Chạm ô: xếp / bỏ ca · Chạm tên ca: chọn nhiều người · Giữ ô: chi tiết'
              : 'Chạm ô để xếp / bỏ ca · Chạm tên ca để chọn nhiều nhân viên cùng lúc · Giữ ô hoặc chạm tên nhân viên để xem chi tiết, duyệt đăng ký'),
          style: const TextStyle(fontSize: 11, color: SboxColors.slate500),
        ),
      ]);
    });
  }

  // ── Đầu cột ──

  Widget _shiftHeader(Map<String, dynamic> t) {
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    final cv = data.cov(day, t['id'].toString());
    final status = cv?['status']?.toString();
    final eff = ShiftUi.n(cv?['effective']).toInt();
    final hasQuota = cv?['hasQuota'] == true;
    final min = ShiftUi.n(cv?['min']).toInt(), max = ShiftUi.n(cv?['max']).toInt();
    final covText = hasQuota ? '$eff/${min == max ? '$min' : '$min–$max'}' : '$eff người';
    return Tooltip(
      message: tr('Chọn nhân viên cho ${t['name']}'),
      child: InkWell(
        onTap: () => onShiftHeader(t),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: SboxColors.slate100))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Container(width: 3, height: 13, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Expanded(
                // Cột hẹp (điện thoại): tên ca 2 dòng thay vì cắt «Ca s…».
                child: Text(t['name'].toString(),
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 10.5 : 12.5, height: 1.1, fontWeight: FontWeight.w800, color: SboxColors.slate800)),
              ),
              if (!compact) const Icon(Icons.group_add_rounded, size: 15, color: SboxColors.slate400),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${t['start']}–${t['end']}', maxLines: 1, style: TextStyle(fontSize: compact ? 10 : 11, color: SboxColors.slate500)),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ShiftUi.pill(covText, ShiftUi.coverageColor(status)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _offHeader(List<Map<String, dynamic>> emps) {
    final n = emps.where((e) => BoardData.dayOffItem(BoardData.cell(e, day)) != null).length;
    return Container(
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: SboxColors.slate100))),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.weekend_rounded, size: 15, color: SboxColors.slate500),
        Text(tr('Nghỉ'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SboxColors.slate600)),
        Text('$n', style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
      ]),
    );
  }

  // ── Ô ──

  Widget _nameCell(Map<String, dynamic> e) {
    final c = BoardData.cell(e, day);
    final lv = BoardData.leave(c);
    final reg = BoardData.registration(c);
    final full = e['name']?.toString() ?? '';
    final name = compact ? _shortName(full) : full;
    Widget? flag;
    if (lv != null) {
      flag = ShiftUi.pill(lv['status'] == 'Approved' ? 'Nghỉ phép' : 'Xin nghỉ', ShiftUi.statusColor(lv['status']?.toString()));
    } else if (reg != null) {
      flag = ShiftUi.pill('Đăng ký chờ', SboxColors.warning);
    } else if (c?['swapPending'] == true) {
      flag = ShiftUi.pill('Đổi ca', SboxColors.violet);
    }
    // Mã NV giúp phân biệt người trùng tên; có bộ phận thì ghi kèm.
    final dept = [e['code'], e['department']].map((x) => '${x ?? ''}'.trim()).where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => onDetail(e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: compact ? 12.5 : 13, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
          if (flag != null)
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: flag)
          else if (dept.isNotEmpty)
            Text(dept, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
        ]),
      ),
    );
  }

  Widget _shiftCell(Map<String, dynamic> e, Map<String, dynamic> t) {
    final tid = t['id'].toString();
    final c = BoardData.cell(e, day);
    final item = BoardData.shiftItem(c, tid);
    final reg = BoardData.registration(c);
    final regHere = reg != null && reg['isDayOff'] != true && reg['shiftId']?.toString() == tid;
    final onLeave = BoardData.leaveApproved(c);
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    final isBusy = busy.contains(busyKey(e['id'], day, tid));

    Widget body;
    if (isBusy) {
      body = const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (item != null) {
      final muted = onLeave ? SboxColors.slate400 : color;
      body = Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: muted.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: muted, width: 1.3),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(onLeave ? Icons.beach_access_rounded : Icons.check_rounded, size: compact ? 18 : 16, color: muted),
          if (!compact) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(onLeave ? tr('Nghỉ phép') : '${t['start']}–${t['end']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.slate800)),
            ),
          ],
        ]),
      );
    } else if (regHere) {
      body = Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: SboxColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SboxColors.warning, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(tr(compact ? '?' : 'Chờ duyệt'),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SboxColors.warning)),
      );
    } else if (onLeave) {
      body = const Center(child: Icon(Icons.remove_rounded, size: 16, color: SboxColors.slate300));
    } else {
      body = const Center(child: Icon(Icons.add_rounded, size: 18, color: SboxColors.slate300));
    }
    return InkWell(
      onTap: isBusy ? null : () => (regHere || onLeave) ? onDetail(e) : onToggleShift(e, t),
      onLongPress: () => onDetail(e),
      child: Container(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: SboxColors.slate100))),
        child: body,
      ),
    );
  }

  Widget _offCell(Map<String, dynamic> e) {
    final c = BoardData.cell(e, day);
    final off = BoardData.dayOffItem(c) != null;
    final reg = BoardData.registration(c);
    final regOff = reg != null && reg['isDayOff'] == true;
    final isBusy = busy.contains(busyKey(e['id'], day, 'off'));
    Widget body;
    if (isBusy) {
      body = const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (off) {
      body = Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: const Icon(Icons.weekend_rounded, size: 16, color: SboxColors.slate600),
      );
    } else if (regOff) {
      body = const Center(
        child: Text('?', style: TextStyle(fontWeight: FontWeight.w800, color: SboxColors.warning)),
      );
    } else {
      body = const Center(child: Icon(Icons.add_rounded, size: 16, color: SboxColors.slate200));
    }
    return InkWell(
      onTap: isBusy ? null : () => regOff ? onDetail(e) : onToggleDayOff(e),
      onLongPress: () => onDetail(e),
      child: Container(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: SboxColors.slate100))),
        child: body,
      ),
    );
  }

  /// «Trương Gia Bảo» → «Gia Bảo» khi cột hẹp.
  static String _shortName(String full) {
    final p = full.trim().split(RegExp(r'\s+'));
    return p.length >= 3 ? p.sublist(p.length - 2).join(' ') : full;
  }
}
