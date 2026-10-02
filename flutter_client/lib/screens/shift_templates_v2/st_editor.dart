import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'st_common.dart';
import 'st_salary.dart';

/// Trang tạo / sửa ca: 1 Giờ ca · 2 Quy tắc chấm công · 3 Lương ca · 4 Trạng thái.
/// Bên phải (máy tính) / trên cùng (điện thoại) là minh họa trực tiếp theo số đang nhập.
class ShiftTemplateEditorPage extends StatefulWidget {
  const ShiftTemplateEditorPage({super.key, this.shift, this.usage});

  /// null = tạo ca mới.
  final ShiftTpl? shift;
  final ShiftUsage? usage;

  @override
  State<ShiftTemplateEditorPage> createState() => _ShiftTemplateEditorPageState();
}

enum _BreakMode { none, window, flexible }

class _ShiftTemplateEditorPageState extends State<ShiftTemplateEditorPage> {
  final _api = ApiService();
  late final ShiftTpl _s;
  late final String _original;
  late final String _origRules;
  late final String _title;
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _desc;
  late _BreakMode _breakMode;
  bool _saving = false;
  bool _showPreview = false;

  bool get _isNew => widget.shift == null;
  bool get _dirty => _snapshot() != _original;

  @override
  void initState() {
    super.initState();
    _s = widget.shift ?? ShiftTpl(id: '', name: '', start: 8 * 60, end: 17 * 60, lunchStart: 12 * 60, lunchEnd: 13 * 60);
    _name = TextEditingController(text: _s.name);
    _code = TextEditingController(text: _s.code == _s.name ? '' : (_s.code ?? ''));
    _desc = TextEditingController(text: _s.description ?? '');
    _breakMode = _s.hasLunchWindow ? _BreakMode.window : (_s.breakMinutes > 0 ? _BreakMode.flexible : _BreakMode.none);
    _original = _snapshot();
    _origRules = _rulesKey(_s);
    _title = _isNew ? 'Thêm ca làm việc' : 'Sửa ca: ${_s.name}';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _snapshot() {
    _sync();
    return _s.toJson().toString();
  }

  void _sync() {
    _s
      ..name = _name.text
      ..code = _code.text
      ..description = _desc.text;
  }

  void _set(VoidCallback f) => setState(() {
        f();
        if (_s.overnight && _s.type == ShiftKind.office) _s.type = ShiftKind.overnight;
      });

  /// Khóa so sánh giờ + quy tắc (bỏ tên, mã, ghi chú, trạng thái).
  static String _rulesKey(ShiftTpl s) {
    final j = Map.of(s.toJson())
      ..remove('name')
      ..remove('code')
      ..remove('description')
      ..remove('isActive');
    return j.toString();
  }

  /// Đã đổi giờ / quy tắc của ca đã có lịch.
  bool get _rulesChanged => widget.usage?.hasData == true && _rulesKey(_s) != _origRules;

  Future<void> _pickTime(int current, ValueChanged<int> onPicked) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60 % 24, minute: current % 60),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) _set(() => onPicked(t.hour * 60 + t.minute));
  }

  void _setBreakMode(_BreakMode m) => _set(() {
        _breakMode = m;
        switch (m) {
          case _BreakMode.none:
            _s
              ..lunchStart = null
              ..lunchEnd = null
              ..breakMinutes = 0;
          case _BreakMode.window:
            final len = _s.breakMinutes > 0 ? _s.breakMinutes : 60;
            final (a, b) = StTime.centerBreak(_s.start, _s.end, len);
            _s
              ..lunchStart = a
              ..lunchEnd = b;
          case _BreakMode.flexible:
            _s
              ..breakMinutes = _s.effectiveBreak > 0 ? _s.effectiveBreak : 30
              ..lunchStart = null
              ..lunchEnd = null;
        }
      });

  Future<void> _save() async {
    _sync();
    final err = _s.validate();
    if (err != null) {
      stToast(context, err, error: true);
      return;
    }
    if (_rulesChanged) {
      final u = widget.usage!;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: SboxColors.warning),
          title: Text(tr('Đổi giờ / quy tắc của ca đang dùng?')),
          content: Text(tr('Ca đã có ${u.schedules} lịch của ${u.employees} nhân viên. Thay đổi giờ ca hoặc quy tắc chấm công '
              'có thể làm thay đổi kết quả tổng hợp công những ngày chưa chốt lương.\n\n'
              'Muốn giữ nguyên quá khứ: dùng «Nhân bản» để tạo ca mới với giờ mới, rồi ngừng dùng ca cũ.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Xem lại'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn lưu'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    final data = _s.toJson();
    final r = _isNew ? await _api.createShift(data) : await _api.updateShift(_s.id, data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      stToast(context, _isNew ? 'Đã tạo ca ${_s.name}' : 'Đã lưu ca ${_s.name}');
      Navigator.of(context).pop(true);
    } else {
      stToast(context, r['message']?.toString() ?? 'Không lưu được ca', error: true);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ thay đổi?')),
        content: Text(tr('Ca chưa được lưu.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ở lại'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ thay đổi'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    final err = _s.validate();
    final form = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 16, wide ? 12 : 12, 100),
      children: [
        if (!wide) _mobilePreview(),
        if (widget.usage?.hasData == true) _usageBanner(widget.usage!),
        _section(1, 'Giờ ca', 'Tên, loại ca, giờ vào – ra và nghỉ giữa ca', _timeSection()),
        _section(2, 'Quy tắc chấm công', 'Khi nào nhận chấm, tính trễ, về sớm, tăng ca', _rulesSection()),
        _section(3, 'Lương ca', 'Mức lương riêng cho ca này (không bắt buộc)', _salarySection()),
        _section(4, 'Trạng thái & ghi chú', null, _statusSection()),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: SboxColors.slate50,
        appBar: AppBar(
          title: Text(tr(_title)),
          actions: [
            if (wide)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SboxButton(label: 'Lưu ca', icon: Icons.check_rounded, loading: _saving, onPressed: _saving ? null : _save),
              ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: SboxColors.slate200))),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        err == null ? '${StTime.hm(_s.start)}–${StTime.hm(_s.end)} · ${StTime.duration(_s.workMinutes)} làm' : tr(err),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: err == null ? SboxColors.slate700 : SboxColors.dangerText),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SboxButton(label: 'Lưu ca', icon: Icons.check_rounded, loading: _saving, onPressed: _saving ? null : _save),
                  ]),
                ),
              ),
        body: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: form),
                SizedBox(
                  width: 400,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 24, 24), children: [_previewCard()]),
                ),
              ])
            : form,
      ),
    );
  }

  // ─── Khung chung ───────────────────────────────────────────────

  Widget _section(int step, String title, String? sub, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SboxCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: SboxColors.brand600, shape: BoxShape.circle),
                child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  if (sub != null) Text(tr(sub), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );

  Widget _usageBanner(ShiftUsage u) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SboxColors.warningSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.warning.withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, color: SboxColors.warningText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Ca đang dùng: ${u.employees} nhân viên, ${u.schedules} lịch'
                    '${u.upcoming > 0 ? ' (${u.upcoming} lịch sắp tới)' : ''}. '
                    'Đổi giờ hoặc quy tắc sẽ ảnh hưởng cách tính công các ngày chưa chốt lương.'),
                style: const TextStyle(fontSize: 12.5, color: SboxColors.warningText, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      );

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: tr(label),
        hintText: hint == null ? null : tr(hint),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _timeButton(String label, int value, ValueChanged<int> onPicked, {String? suffix}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickTime(value, onPicked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.slate200),
            color: Colors.white,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
            Row(children: [
              Text(StTime.hm(value), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(tr(suffix), style: const TextStyle(fontSize: 11.5, color: SboxColors.violet))),
              ],
            ]),
          ]),
        ),
      );

  // ─── 1. Giờ ca ─────────────────────────────────────────────────

  Widget _timeSection() {
    final s = _s;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_isNew) ...[
        Text(tr('Mẫu nhanh'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
          for (final p in ShiftPreset.all) Padding(padding: const EdgeInsets.only(right: 8), child:
            ActionChip(
              avatar: Icon(p.type.icon, size: 16, color: p.type.tone.fg),
              label: Text('${tr(p.name)}  ${StTime.hm(p.start)}–${StTime.hm(p.end)}'),
              onPressed: () => _set(() {
                _sync();
                p.applyTo(s);
                _name.text = s.name;
                _code.text = s.code ?? '';
                _breakMode = s.hasLunchWindow ? _BreakMode.window : (s.breakMinutes > 0 ? _BreakMode.flexible : _BreakMode.none);
              }),
            )),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      Row(children: [
        Expanded(flex: 3, child: TextField(controller: _name, decoration: _dec('Tên ca *', hint: 'VD: Ca sáng'), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: TextField(controller: _code, decoration: _dec('Mã ca', hint: 'Bỏ trống = theo tên'))),
      ]),
      const SizedBox(height: 14),
      Text(tr('Loại ca'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in ShiftKind.values)
          ChoiceChip(
            avatar: Icon(k.icon, size: 16, color: s.type == k ? k.tone.fg : SboxColors.slate400),
            label: Text(tr(k.label)),
            selected: s.type == k,
            showCheckmark: false,
            selectedColor: k.tone.bg,
            onSelected: (_) => setState(() => s.type = k),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(tr(s.type.hint), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _timeButton('Giờ vào', s.start, (v) => s.start = v)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: SboxColors.slate400)),
        Expanded(child: _timeButton('Giờ ra', s.end, (v) => s.end = v, suffix: s.overnight ? 'hôm sau' : null)),
      ]),
      if (s.start == s.end)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _set(() => s.end = (s.start - 1 + StTime.day) % StTime.day),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text(tr('Ca gần 24 giờ: đặt giờ ra = giờ vào − 1 phút')),
          ),
        ),
      const SizedBox(height: 12),
      ShiftDayBar(shift: s, height: 16),
      const SizedBox(height: 16),
      Text(tr('Nghỉ giữa ca'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
      const SizedBox(height: 6),
      SegmentedButton<_BreakMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: _BreakMode.none, label: Text(tr('Không nghỉ'))),
          ButtonSegment(value: _BreakMode.window, label: Text(tr('Khung giờ cố định'))),
          ButtonSegment(value: _BreakMode.flexible, label: Text(tr('Linh hoạt'))),
        ],
        selected: {_breakMode},
        onSelectionChanged: (v) => _setBreakMode(v.first),
      ),
      const SizedBox(height: 10),
      if (_breakMode == _BreakMode.window && s.hasLunchWindow) ...[
        Row(children: [
          Expanded(child: _timeButton('Bắt đầu nghỉ', s.lunchStart!, (v) => s.lunchStart = v)),
          const SizedBox(width: 10),
          Expanded(child: _timeButton('Hết nghỉ', s.lunchEnd!, (v) => s.lunchEnd = v)),
        ]),
        Row(children: [
          Expanded(
            child: Text(
              tr(StTime.insideShift(s.start, s.end, s.lunchStart!, s.lunchEnd!)
                  ? 'Không tính công ${StTime.duration(s.effectiveBreak)} trong khung này.'
                  : 'Khung nghỉ đang nằm ngoài giờ ca.'),
              style: TextStyle(
                  fontSize: 12,
                  color: StTime.insideShift(s.start, s.end, s.lunchStart!, s.lunchEnd!)
                      ? SboxColors.slate500
                      : SboxColors.dangerText),
            ),
          ),
          TextButton(
            onPressed: () => _set(() {
              var len = s.lunchEnd! - s.lunchStart!;
              if (len <= 0) len += StTime.day;
              final (a, b) = StTime.centerBreak(s.start, s.end, len);
              s
                ..lunchStart = a
                ..lunchEnd = b;
            }),
            child: Text(tr('Đặt vào giữa ca')),
          ),
        ]),
      ],
      if (_breakMode == _BreakMode.flexible)
        _MinuteStepper(
          label: 'Số phút nghỉ',
          hint: 'Nghỉ lúc nào cũng được, trừ đủ số phút này khi tính công',
          value: s.breakMinutes,
          max: 240,
          onChanged: (v) => _set(() => s.breakMinutes = v),
        ),
    ]);
  }

  // ─── 2. Quy tắc ───────────────────────────────────────────────

  Widget _rulesSection() {
    final s = _s;
    final isOt = s.type == ShiftKind.overtime;
    final steppers = <Widget>[
      _MinuteStepper(
        label: 'Nhận chấm sớm',
        hint: 'Chấm vào sớm tối đa bao nhiêu phút vẫn khớp ca',
        value: s.earlyCheckIn,
        onChanged: (v) => _set(() => s.earlyCheckIn = v),
      ),
      if (!isOt) ...[
        _MinuteStepper(
          label: 'Miễn trễ',
          hint: 'Vào trễ trong khoảng này không tính đi trễ',
          value: s.lateGrace,
          onChanged: (v) => _set(() => s.lateGrace = v),
        ),
        _MinuteStepper(
          label: 'Giới hạn đi trễ',
          hint: 'Trễ quá mốc này không còn thuộc ca',
          value: s.maxLate,
          onChanged: (v) => _set(() => s.maxLate = v),
        ),
        _MinuteStepper(
          label: 'Miễn về sớm',
          hint: 'Ra sớm trong khoảng này không tính về sớm',
          value: s.earlyLeaveGrace,
          onChanged: (v) => _set(() => s.earlyLeaveGrace = v),
        ),
        _MinuteStepper(
          label: 'Giới hạn về sớm',
          hint: 'Về sớm quá mốc này không còn thuộc ca',
          value: s.maxEarlyLeave,
          onChanged: (v) => _set(() => s.maxEarlyLeave = v),
        ),
        _MinuteStepper(
          label: 'Tăng ca trước ca',
          hint: 'Vào sớm hơn số phút này mới tính tăng ca (0 = không tính)',
          value: s.otBefore,
          onChanged: (v) => _set(() => s.otBefore = v),
        ),
        _MinuteStepper(
          label: 'Tăng ca sau ca',
          hint: 'Ra muộn hơn số phút này mới tính tăng ca',
          value: s.otAfter,
          onChanged: (v) => _set(() => s.otAfter = v),
        ),
      ],
    ];
    final needFix = s.otBefore > 0 && s.earlyCheckIn <= s.otBefore && !isOt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (isOt)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr('Ca tăng ca: không tính đi trễ / về sớm, toàn bộ giờ làm là tăng ca.'),
              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
        ),
      LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth >= 560;
        if (!two) return Column(children: steppers);
        final w = (box.maxWidth - 16) / 2;
        return Wrap(spacing: 16, children: [for (final x in steppers) SizedBox(width: w, child: x)]);
      }),
      if (needFix)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: SboxColors.dangerText, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('«Nhận chấm sớm» phải lớn hơn «Tăng ca trước ca» thì mới tính được tăng ca trước ca.'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.dangerText)),
            ),
            TextButton(
              onPressed: () => _set(() => s.earlyCheckIn = s.otBefore + 1),
              child: Text(tr('Đặt ${s.otBefore + 1} phút')),
            ),
          ]),
        ),
    ]);
  }

  // ─── 3. Lương ca ──────────────────────────────────────────────

  Widget _salarySection() {
    if (_isNew) {
      return Text(tr('Lưu ca trước, sau đó mở lại ca để thêm mức lương ca (lương cố định, theo giờ hoặc nhân hệ số).'),
          style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500));
    }
    return ShiftSalaryLevelsPanel(shiftId: _s.id, shiftName: _s.name);
  }

  // ─── 4. Trạng thái ────────────────────────────────────────────

  Widget _statusSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _s.isActive,
          onChanged: (v) => setState(() => _s.isActive = v),
          title: Text(tr(_s.isActive ? 'Đang dùng' : 'Ngừng dùng'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr(_s.isActive
              ? 'Ca hiện khi xếp ca, đăng ký ca'
              : 'Ẩn khỏi xếp ca mới; lịch, chấm công, lương đã có giữ nguyên')),
        ),
        const SizedBox(height: 6),
        TextField(controller: _desc, maxLines: 2, decoration: _dec('Ghi chú', hint: 'VD: Áp dụng cho bộ phận kho')),
      ]);

  // ─── Minh họa ─────────────────────────────────────────────────

  Widget _previewBody() {
    final s = _s;
    final warns = s.warnings();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(s.type.icon, color: s.type.tone.fg, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tr(_name.text.trim().isEmpty ? 'Ca mới' : _name.text.trim()),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        SboxStatusChip(label: s.type.label, tone: s.type.tone),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 4, children: [
        _kv('Khung ca', '${StTime.hm(s.start)}–${StTime.hm(s.end)}'),
        _kv('Giờ làm', StTime.duration(s.workMinutes)),
        if (s.effectiveBreak > 0) _kv('Nghỉ', StTime.duration(s.effectiveBreak)),
      ]),
      const SizedBox(height: 10),
      ShiftDayBar(shift: s),
      const Divider(height: 22),
      ShiftRuleTimeline(shift: s),
      for (final w in warns)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: SboxColors.warningText),
            const SizedBox(width: 6),
            Expanded(child: Text(tr(w), style: const TextStyle(fontSize: 12, color: SboxColors.warningText))),
          ]),
        ),
    ]);
  }

  Widget _kv(String k, String v) => Text.rich(
        TextSpan(style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500), children: [
          TextSpan(text: '${tr(k)}: '),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate900)),
        ]),
      );

  Widget _previewCard() => SboxCard(
        title: 'Minh họa chấm công',
        subtitle: 'Cập nhật theo số bạn đang nhập',
        child: _previewBody(),
      );

  Widget _mobilePreview() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SboxCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: () => setState(() => _showPreview = !_showPreview),
              child: Row(children: [
                const Icon(Icons.timeline_rounded, color: SboxColors.brand600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Minh họa chấm công'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text(tr(_showPreview ? 'Thu gọn' : 'Xem'), style: const TextStyle(color: SboxColors.brand600, fontWeight: FontWeight.w700)),
                Icon(_showPreview ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: SboxColors.brand600),
              ]),
            ),
            if (_showPreview) ...[
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.only(right: 8), child: _previewBody()),
            ],
          ]),
        ),
      );
}

/// Ô số phút có nút − / +.
class _MinuteStepper extends StatefulWidget {
  const _MinuteStepper({required this.label, required this.value, required this.onChanged, this.hint, this.max = 600});

  final String label;
  final String? hint;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_MinuteStepper> createState() => _MinuteStepperState();
}

class _MinuteStepperState extends State<_MinuteStepper> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _MinuteStepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != '${widget.value}') _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _emit(int v) {
    final x = v.clamp(0, widget.max);
    _c.text = '$x';
    widget.onChanged(x);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(widget.label), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            if (widget.hint != null)
              Text(tr(widget.hint!), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: SboxColors.slate200),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _btn(Icons.remove_rounded, () => _emit(widget.value - 5)),
            SizedBox(
              width: 44,
              child: TextField(
                controller: _c,
                focusNode: _focus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                style: const TextStyle(fontWeight: FontWeight.w800),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                onChanged: (v) => widget.onChanged((int.tryParse(v) ?? 0).clamp(0, widget.max)),
              ),
            ),
            _btn(Icons.add_rounded, () => _emit(widget.value + 5)),
          ]),
        ),
        const SizedBox(width: 6),
        Text(tr('phút'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
      ]),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 18, color: SboxColors.slate600)),
      );
}
