import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'st_common.dart';
import 'st_editor.dart';

/// Ca mẫu (thiết lập ca): danh sách thẻ có thanh 24 giờ, mức sử dụng, nhân bản, ngừng dùng,
/// xóa an toàn (chỉ ca chưa phát sinh dữ liệu; xóa thì gỡ khỏi thiết lập lương).
class ShiftTemplatesV2Screen extends StatefulWidget {
  const ShiftTemplatesV2Screen({super.key});

  @override
  State<ShiftTemplatesV2Screen> createState() => _ShiftTemplatesV2ScreenState();
}

enum _Filter { all, active, inactive, overnight, unused }

class _ShiftTemplatesV2ScreenState extends State<ShiftTemplatesV2Screen> {
  final _api = ApiService();
  List<ShiftTpl> _shifts = [];
  Map<String, ShiftUsage> _usage = {};
  Map<String, int> _levelCount = {};
  bool _loading = true;
  String? _error;
  String _q = '';
  _Filter _filter = _Filter.all;

  bool _can(String action) {
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return switch (action) {
        'create' => p.canCreate('ShiftSetup') || p.canCreate('ShiftTemplate'),
        'edit' => p.canEdit('ShiftSetup') || p.canEdit('ShiftTemplate'),
        _ => p.canDelete('ShiftSetup') || p.canDelete('ShiftTemplate'),
      };
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      _api.getShifts(),
      _api.getShiftTemplateUsage(),
      _api.getShiftSalaryLevels(),
    ]);
    if (!mounted) return;
    final list = results[0] as List<dynamic>;
    final usage = results[1] as Map<String, dynamic>;
    final levels = results[2] as Map<String, dynamic>;
    final u = <String, ShiftUsage>{};
    if (usage['isSuccess'] == true && usage['data'] is List) {
      for (final r in (usage['data'] as List).whereType<Map>()) {
        u[r['shiftId'].toString()] = ShiftUsage(Map<String, dynamic>.from(r));
      }
    }
    final lc = <String, int>{};
    final ld = levels['data'];
    final items = ld is Map ? ld['items'] : ld;
    if (items is List) {
      for (final l in items.whereType<Map>()) {
        final k = l['shiftTemplateId']?.toString() ?? '';
        lc[k] = (lc[k] ?? 0) + 1;
      }
    }
    setState(() {
      _shifts = [for (final s in list.whereType<Map>()) ShiftTpl.fromJson(Map<String, dynamic>.from(s))]
        ..sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return a.start.compareTo(b.start);
        });
      _usage = u;
      _levelCount = lc;
      _loading = false;
      if (list.isEmpty && usage['isSuccess'] != true) _error = usage['message']?.toString();
    });
  }

  ShiftUsage _u(ShiftTpl s) => _usage[s.id] ?? ShiftUsage.empty;

  List<ShiftTpl> get _visible {
    final q = _q.trim().toLowerCase();
    return _shifts.where((s) {
      if (q.isNotEmpty && !s.name.toLowerCase().contains(q) && !(s.code ?? '').toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.active => s.isActive,
        _Filter.inactive => !s.isActive,
        _Filter.overnight => s.overnight,
        _Filter.unused => !_u(s).hasData,
      };
    }).toList();
  }

  Future<void> _openEditor([ShiftTpl? shift]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShiftTemplateEditorPage(shift: shift?.copy(), usage: shift == null ? null : _u(shift)),
    ));
    if (saved == true) _load();
  }

  Future<void> _duplicate(ShiftTpl s) async {
    final r = await _api.duplicateShiftTemplate(s.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      stToast(context, 'Đã tạo ${(r['data'] as Map?)?['name'] ?? 'bản sao'}');
      _load();
    } else {
      stToast(context, r['message']?.toString() ?? 'Không nhân bản được', error: true);
    }
  }

  Future<void> _toggleActive(ShiftTpl s) async {
    final u = _u(s);
    if (s.isActive && u.upcoming > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Ngừng dùng ca "${s.name}"?')),
          content: Text(tr('Ca còn ${u.upcoming} lịch từ hôm nay trở đi. Lịch đã xếp vẫn giữ nguyên, '
              'nhưng ca sẽ không hiện khi xếp ca mới hoặc đăng ký ca.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ngừng dùng'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final r = await _api.setShiftTemplateActive(s.id, !s.isActive);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      stToast(context, s.isActive ? 'Đã ngừng dùng ca ${s.name}' : 'Đã dùng lại ca ${s.name}');
      _load();
    } else {
      stToast(context, r['message']?.toString() ?? 'Không cập nhật được', error: true);
    }
  }

  Future<void> _delete(ShiftTpl s) async {
    final u = _u(s);
    if (u.hasData) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lock_outline_rounded, color: SboxColors.warning),
          title: Text(tr('Không xóa được ca "${s.name}"')),
          content: Text(tr('Ca đã phát sinh dữ liệu: ${u.dataSummary}. Xóa sẽ làm sai lịch sử chấm công và lương.\n\n'
              'Hãy «Ngừng dùng» để ẩn ca khỏi xếp ca mới mà vẫn giữ lịch sử.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
            if (s.isActive && _can('edit'))
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _toggleActive(s);
                },
                child: Text(tr('Ngừng dùng')),
              ),
          ],
        ),
      );
      return;
    }
    final cfg = u.configParts;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: SboxColors.danger),
        title: Text(tr('Xóa ca "${s.name}"?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Ca chưa phát sinh lịch, chấm công hay đơn từ nào.')),
          if (cfg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tr('Đồng thời gỡ ca khỏi thiết lập:'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final c in cfg) Text('•  ${tr(c)}'),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa ca')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.deleteShift(s.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      stToast(context, 'Đã xóa ca ${s.name}');
      _load();
    } else {
      stToast(context, r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final canCreate = _can('create');
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(icon: Icons.refresh_rounded, label: 'Làm mới', onPressed: _load),
        if (canCreate)
          HrmTopBarAction(icon: Icons.add, label: 'Thêm ca', primary: true, showLabel: true, onPressed: () => _openEditor()),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: _loading
            ? const SboxLoading(message: 'Đang tải ca làm việc…')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 16, wide ? 24 : 12, 96),
                  children: [
                    _summary(wide),
                    const SizedBox(height: 14),
                    _toolbar(wide),
                    const SizedBox(height: 12),
                    if (_error != null)
                      SboxEmptyState(icon: Icons.cloud_off_rounded, title: 'Không tải được danh sách ca', message: _error)
                    else if (_shifts.isEmpty)
                      SboxEmptyState(
                        icon: Icons.schedule_rounded,
                        title: 'Chưa có ca làm việc',
                        message: 'Tạo ca đầu tiên từ mẫu nhanh: Hành chính, Ca sáng, Ca chiều, Ca đêm…',
                        action: canCreate
                            ? SboxButton(label: 'Thêm ca', icon: Icons.add, onPressed: () => _openEditor())
                            : null,
                      )
                    else if (_visible.isEmpty)
                      const SboxEmptyState(icon: Icons.search_off_rounded, title: 'Không có ca phù hợp')
                    else
                      _grid(wide),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summary(bool wide) {
    final active = _shifts.where((s) => s.isActive).length;
    final used = _shifts.where((s) => _u(s).upcoming > 0).length;
    final emps = _usage.values.fold<int>(0, (a, u) => a + u.employees);
    final cards = [
      SboxMetricCard(label: 'Ca đang dùng', value: '$active/${_shifts.length}', icon: Icons.schedule_rounded),
      SboxMetricCard(label: 'Ca có lịch sắp tới', value: '$used', icon: Icons.event_available_rounded, tone: SboxTone.success),
      SboxMetricCard(label: 'Lượt NV đã xếp ca', value: '$emps', icon: Icons.groups_rounded, tone: SboxTone.violet),
    ];
    if (!wide) {
      // Điện thoại: 3 số trên 1 hàng (không cuộn ngang, không cắt thẻ).
      return SboxStatRow(items: [
        SboxKpi(label: 'Ca đang dùng', value: '$active/${_shifts.length}'),
        SboxKpi(label: 'Có lịch sắp tới', value: '$used', tone: SboxTone.success),
        SboxKpi(label: 'Lượt NV đã xếp', value: '$emps', tone: SboxTone.violet),
      ]);
    }
    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  Widget _toolbar(bool wide) {
    final search = TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        hintText: tr('Tìm theo tên hoặc mã ca'),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SboxColors.slate200)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SboxColors.slate200)),
      ),
    );
    String label(_Filter f) => switch (f) {
          _Filter.all => 'Tất cả (${_shifts.length})',
          _Filter.active => 'Đang dùng',
          _Filter.inactive => 'Ngừng dùng',
          _Filter.overnight => 'Qua đêm',
          _Filter.unused => 'Chưa phát sinh dữ liệu',
        };
    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in _Filter.values)
        ChoiceChip(
          label: Text(tr(label(f))),
          selected: _filter == f,
          onSelected: (_) => setState(() => _filter = f),
          selectedColor: SboxColors.brand50,
          labelStyle: TextStyle(
              fontWeight: _filter == f ? FontWeight.w700 : FontWeight.w500,
              color: _filter == f ? SboxColors.brand700 : SboxColors.slate600),
          side: BorderSide(color: _filter == f ? SboxColors.brand200 : SboxColors.slate200),
          showCheckmark: false,
        ),
    ]);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 320, child: search),
        const SizedBox(width: 16),
        Expanded(child: chips),
      ]);
    }
    // Điện thoại: ô tìm + nút lọc trên 1 hàng — đủ 5 lựa chọn trong menu (không khuất ngoài màn hình).
    final on = _filter != _Filter.all;
    return Row(children: [
      Expanded(child: search),
      const SizedBox(width: 8),
      PopupMenuButton<_Filter>(
        tooltip: tr('Lọc ca'),
        initialValue: _filter,
        onSelected: (f) => setState(() => _filter = f),
        itemBuilder: (_) => [
          for (final f in _Filter.values)
            CheckedPopupMenuItem(value: f, checked: _filter == f, child: Text(tr(label(f)))),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? SboxColors.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? SboxColors.brand200 : SboxColors.slate200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune_rounded, size: 18, color: on ? SboxColors.brand700 : SboxColors.slate600),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(tr(on ? label(_filter) : 'Lọc'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? SboxColors.brand700 : SboxColors.slate700)),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _grid(bool wide) {
    final items = _visible;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1300 ? 3 : (box.maxWidth >= 760 ? 2 : 1);
      if (cols == 1) {
        return Column(children: [
          for (final s in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(s)),
        ]);
      }
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final s in items) SizedBox(width: w, child: _card(s)),
      ]);
    });
  }

  Widget _card(ShiftTpl s) {
    final u = _u(s);
    final levels = _levelCount[s.id] ?? 0;
    final canEdit = _can('edit');
    final canDelete = _can('delete');
    final canCreate = _can('create');
    Widget stat(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: SboxColors.slate400),
          const SizedBox(width: 4),
          Text(tr(text), style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
        ]);
    return SboxCard(
      onTap: canEdit ? () => _openEditor(s) : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: s.type.tone.bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(s.type.icon, color: s.type.tone.fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(tr(s.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: s.isActive ? SboxColors.slate900 : SboxColors.slate400)),
                ),
                if ((s.code ?? '').isNotEmpty && s.code != s.name) ...[
                  const SizedBox(width: 6),
                  Text(s.code!, style: const TextStyle(fontSize: 12, color: SboxColors.slate400, fontWeight: FontWeight.w600)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                '${StTime.hm(s.start)} – ${StTime.hm(s.end)}${s.overnight ? ' (hôm sau)' : ''}  ·  ${StTime.duration(s.workMinutes)} làm',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate700),
              ),
            ]),
          ),
          if (!s.isActive)
            const SboxStatusChip(label: 'Ngừng dùng', tone: SboxTone.neutral, dot: true)
          else
            SboxStatusChip(label: s.type.label, tone: s.type.tone),
          PopupMenuButton<String>(
            tooltip: tr('Thao tác'),
            icon: const Icon(Icons.more_vert_rounded, color: SboxColors.slate500),
            onSelected: (v) => switch (v) {
              'edit' => _openEditor(s),
              'dup' => _duplicate(s),
              'active' => _toggleActive(s),
              _ => _delete(s),
            },
            itemBuilder: (_) => [
              if (canEdit) _menu('edit', Icons.edit_outlined, 'Sửa ca'),
              if (canCreate) _menu('dup', Icons.copy_rounded, 'Nhân bản'),
              if (canEdit)
                _menu('active', s.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    s.isActive ? 'Ngừng dùng' : 'Dùng lại'),
              if (canDelete)
                _menu('delete', u.hasData ? Icons.lock_outline_rounded : Icons.delete_outline_rounded,
                    u.hasData ? 'Xóa (đã có dữ liệu)' : 'Xóa ca', danger: !u.hasData),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.only(right: 8), child: ShiftDayBar(shift: s)),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          stat(Icons.login_rounded, 'Nhận chấm sớm ${s.earlyCheckIn}p'),
          if (s.type != ShiftKind.overtime) stat(Icons.timer_outlined, 'Miễn trễ ${s.lateGrace}p'),
          if (s.effectiveBreak > 0) stat(Icons.restaurant_rounded, 'Nghỉ ${StTime.duration(s.effectiveBreak)}'),
          if (levels > 0) stat(Icons.payments_outlined, '$levels mức lương ca'),
        ]),
        const Divider(height: 20, color: SboxColors.divider),
        Row(children: [
          Icon(u.hasData ? Icons.event_note_rounded : Icons.fiber_new_rounded,
              size: 15, color: u.hasData ? SboxColors.brand600 : SboxColors.slate400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(u.hasData
                  ? '${u.employees} NV · ${u.schedules} lịch${u.upcoming > 0 ? ' · ${u.upcoming} sắp tới' : ''}'
                      '${u.lastUsed != null ? ' · gần nhất ${stDate(u.lastUsed!)}' : ''}'
                  : 'Chưa phát sinh dữ liệu — xóa được'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: u.hasData ? SboxColors.slate600 : SboxColors.slate400),
            ),
          ),
        ]),
      ]),
    );
  }

  PopupMenuItem<String> _menu(String v, IconData icon, String label, {bool danger = false}) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, size: 18, color: danger ? SboxColors.danger : SboxColors.slate600),
          const SizedBox(width: 10),
          Text(tr(label), style: TextStyle(color: danger ? SboxColors.danger : null)),
        ]),
      );
}
