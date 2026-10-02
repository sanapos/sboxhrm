import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/overtime_hourly_base_utils.dart';
import '../../utils/travel_salary_utils.dart';
import '../../widgets/settings/settings_page.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../allowance_settings_screen.dart';
import 'sl_common.dart';
import 'sl_model.dart';

/// Mở form thiết lập lương cho một nhân viên. Trả về true khi đã lưu.
Future<bool> showSalaryEditor(
  BuildContext context,
  SlContext ctx,
  SlEmployee e, {
  bool canEdit = true,
  VoidCallback? onEditStoreRates,
}) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SalaryEditor(ctx: ctx, employee: e, canEdit: canEdit, onEditStoreRates: onEditStoreRates),
  ));
  return r == true;
}

class SalaryEditor extends StatefulWidget {
  const SalaryEditor({super.key, required this.ctx, required this.employee, this.canEdit = true, this.onEditStoreRates});
  final SlContext ctx;
  final SlEmployee employee;
  final bool canEdit;
  final VoidCallback? onEditStoreRates;

  @override
  State<SalaryEditor> createState() => _SalaryEditorState();
}

class _SalaryEditorState extends State<SalaryEditor> {
  late SalaryDraft _d;
  late String _saved;
  final Map<String, TextEditingController> _money = {};
  late final TextEditingController _hours;
  late final TextEditingController _stdDays;
  late final TextEditingController _leave;
  late final TextEditingController _unpaid;
  bool _saving = false;
  String? _error;

  /// false = đính chính hồ sơ hiện tại; true = đổi lương từ ngày [_from].
  bool _fromDate = false;
  late DateTime _from = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 1);
  }();

  SlContext get _c => widget.ctx;
  SlEmployee get _e => widget.employee;

  String get _snapshot => _d
      .toBenefit(
        name: '',
        fixedAllowanceTotal: 0,
        dailyAllowanceTotal: 0,
        insuranceSettings: _c.insurance,
        storeWeekendRate: 2,
      )
      .toString();

  @override
  void initState() {
    super.initState();
    _d = SalaryDraft.fromBenefit(_e.benefit, defaultHours: _c.stdHours);
    String n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    _hours = TextEditingController(text: n(_d.hoursPerDay));
    _stdDays = TextEditingController(text: '${_d.stdDays}');
    _leave = TextEditingController(text: '${_d.paidLeaveDays}');
    _unpaid = TextEditingController(text: '${_d.unpaidLeaveDays}');
    _saved = _e.configured ? _snapshot : '';
  }

  @override
  void dispose() {
    for (final c in [..._money.values, _hours, _stdDays, _leave, _unpaid]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty => _snapshot != _saved;

  TextEditingController _m(String key, double v) =>
      _money.putIfAbsent(key, () => TextEditingController(text: v == 0 ? '' : settingsMoney(v)));

  Widget _moneyField(String key, double v, ValueChanged<double> on, {double width = 200}) => SettingsMoneyField(
        controller: _m(key, v),
        enabled: widget.canEdit,
        width: width,
        onChanged: (x) => setState(() => on(x)),
      );

  Future<void> _save() async {
    final err = _d.validate();
    if (err != null) return setState(() => _error = err);
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await saveSalaryFor(_c, _e, _d, effectiveFrom: _e.configured && _fromDate ? _from : null);
    if (!mounted) return;
    if (r == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = r;
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || !widget.canEdit) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Bỏ thay đổi?')),
            content: Text(tr('Thiết lập lương chưa được lưu.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ở lại'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ thay đổi'))),
            ],
          ),
        ) ==
        true;
  }

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_e.upcomingFrom != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SettingsNote(
            'Đã lên lịch đổi lương từ ${dmy(_e.upcomingFrom!)}. Xem hoặc hủy ở «Lịch sử thay đổi lương».',
            icon: Icons.schedule_rounded,
            tone: SboxTone.warning,
          ),
        ),
      _mainSection(),
      _otSection(),
      _insuranceSection(),
      _workSection(),
      _allowanceSection(),
      _travelSection(),
      if (_d.kind == SalaryKind.monthly) _leaveSection(),
    ]);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(false);
            },
          ),
          titleSpacing: 0,
          title: Row(children: [
            SlAvatar(_e, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_e.name, style: SboxType.titleSmStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text([_e.code, if (_e.department != null) _e.department!].where((x) => x.isNotEmpty).join(' · '),
                    style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          actions: [
            if (widget.canEdit && !wide)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SboxButton(label: 'Lưu', icon: Icons.check_rounded, size: SboxButtonSize.sm, loading: _saving, onPressed: _saving ? null : _save),
              ),
          ],
        ),
        body: wide
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 12, 40), children: [form])),
                    SizedBox(
                      width: 360,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 20, 24, 40), children: [_estimateCard(), const SizedBox(height: 12), _saveCard()]),
                    ),
                  ]),
                ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: SettingsNote(_error!, icon: Icons.error_outline_rounded, tone: SboxTone.danger)),
                _estimateCard(),
                const SizedBox(height: 12),
                form,
                if (widget.canEdit) ...[const SizedBox(height: 12), _saveCard()],
              ]),
      ),
    );
  }

  Widget _saveCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) ...[SettingsNote(_error!, icon: Icons.error_outline_rounded, tone: SboxTone.danger), const SizedBox(height: 12)],
          if (!widget.canEdit)
            Text(tr('Bạn chỉ có quyền xem thiết lập lương.'), style: SboxType.smallStyle())
          else ...[
            if (_e.configured) ..._applyChoice() else
              Text(tr('Nhân viên chưa có thiết lập lương — chưa tính được bảng lương.'), style: SboxType.smallStyle()),
            const SizedBox(height: 12),
            SboxButton(
              label: _e.configured ? 'Lưu thay đổi' : 'Lưu thiết lập',
              icon: Icons.check_rounded,
              expand: true,
              loading: _saving,
              onPressed: _saving || (_e.configured && !_dirty) ? null : _save,
            ),
            if (_e.configured) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _showHistory,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(tr('Lịch sử thay đổi lương')),
              ),
            ],
          ],
        ]),
      );

  List<Widget> _applyChoice() => [
        Text(tr('Áp dụng thay đổi'), style: SboxType.bodyStrong()),
        const SizedBox(height: 6),
        SettingsSegment<bool>(
          value: _fromDate,
          options: const [(false, 'Sửa hồ sơ hiện tại'), (true, 'Đổi lương từ ngày')],
          onChanged: (v) => setState(() => _fromDate = v),
        ),
        const SizedBox(height: 8),
        if (!_fromDate)
          Text(tr('Dùng khi nhập sai. Áp dụng cho mọi bảng lương chưa chốt đang dùng hồ sơ này.'), style: SboxType.smallStyle())
        else ...[
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _from,
                firstDate: DateTime(DateTime.now().year - 1),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (d != null) setState(() => _from = d);
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(tr('Từ ngày ${dmy(_from)}')),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Từ ${dmy(_from)} tính theo mức mới, trước ngày đó giữ mức cũ — tháng có ngày đổi được tách hai đoạn. Bảng lương đã qua không thay đổi.'),
            style: SboxType.smallStyle(),
          ),
          if (_e.upcomingFrom != null && !_from.isAfter(_e.upcomingFrom!))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Thay đổi đã lên lịch từ ${dmy(_e.upcomingFrom!)} sẽ bị thay thế.'),
                  style: SboxType.smallStyle(SboxColors.warningText)),
            ),
        ],
      ];

  Future<void> _showHistory() async {
    final res = await _c.api.getSalaryHistory(_e.id);
    if (!mounted) return;
    final rows = [for (final x in (res['data'] is List ? res['data'] as List : const [])) if (x is Map) Map<String, dynamic>.from(x)];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(tr('Lịch sử thay đổi lương'), style: SboxType.titleStyle()),
            const SizedBox(height: 8),
            if (rows.isEmpty) Text(tr(res['isSuccess'] == true ? 'Chưa có thay đổi nào.' : 'Không tải được lịch sử.'), style: SboxType.smallStyle()),
            for (final r in rows) _historyTile(ctx, r),
          ]),
        ),
      ),
    );
  }

  Widget _historyTile(BuildContext ctx, Map<String, dynamic> r) {
    final b = r['benefit'] is Map ? Map<String, dynamic>.from(r['benefit'] as Map) : <String, dynamic>{};
    final from = DateTime.tryParse('${r['from']}');
    final to = DateTime.tryParse('${r['to']}');
    final eff = DateTime.tryParse('${r['effectiveDate']}');
    final today = DateTime.now();
    final future = eff != null && eff.isAfter(DateTime(today.year, today.month, today.day));
    final d = SalaryDraft.fromBenefit(b);
    final range = [
      from == null || from.year < 1900 ? 'Từ đầu' : 'Từ ${dmy(from)}',
      if (to != null && to.year < 9000) 'đến ${dmy(to)}' else 'đến nay',
    ].join(' ');
    final amount = d.kind == SalaryKind.shift && d.shiftType == 1 ? 'Lương ca theo bậc' : '${money(d.mainRate)}${d.kind.unit}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(future ? Icons.schedule_rounded : Icons.check_circle_outline_rounded, color: future ? SboxColors.warning : SboxColors.success),
      title: Text('$amount · ${d.kind.label}'),
      subtitle: Text(tr(future ? '$range · sắp áp dụng' : range)),
      trailing: future && widget.canEdit
          ? TextButton(
              onPressed: () async {
                final res = await _c.api.cancelSalaryVersion('${r['id']}');
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (res['isSuccess'] == true) {
                  if (mounted) Navigator.of(context).pop(true);
                } else if (mounted) {
                  setState(() => _error = res['message']?.toString() ?? 'Không hủy được thay đổi.');
                }
              },
              child: Text(tr('Hủy thay đổi')),
            )
          : null,
    );
  }

  Widget _estimateCard() {
    final fa = _c.allowanceTotal(_e, 0);
    final da = _c.allowanceTotal(_e, 1);
    final est = _d.estimate(fixedAllowance: fa, dailyAllowance: da, storeStdDays: _c.stdDays, insuranceSettings: _c.insurance);
    String days(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    Widget line(String l, double v, {bool minus = false, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(tr(l), style: strong ? SboxType.bodyStrong() : SboxType.smallStyle())),
            Text('${minus ? '− ' : ''}${money(v)}', style: strong ? SboxType.titleStyle(SboxColors.brand700) : SboxType.bodyStyle()),
          ]),
        );
    final shiftLevels = _d.kind == SalaryKind.shift && _d.shiftType == 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [SboxColors.brand50, Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.brand100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.calculate_outlined, color: SboxColors.brand700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Ước tính một tháng đủ ${days(est.days)} công'), style: SboxType.titleSmStyle())),
        ]),
        const SizedBox(height: 10),
        if (shiftLevels)
          Text(tr('Lương ca theo bậc: số tiền phụ thuộc ca thực tế — xem ở Bảng lương.'), style: SboxType.smallStyle())
        else ...[
          line(_d.kind == SalaryKind.monthly ? 'Lương cơ bản + hoàn thành' : '${_d.kind.label} × công', est.main),
          if (est.allowances > 0) line('Phụ cấp', est.allowances),
          if (est.insurance > 0) line('BHXH, BHYT, BHTN (10,5%)', est.insurance, minus: true),
          const Divider(height: 18),
          line('Thực nhận ước tính', est.net, strong: true),
          const SizedBox(height: 4),
          Text(tr('Chưa gồm tăng ca, thưởng phạt, tạm ứng và thuế TNCN.'), style: SboxType.captionStyle()),
        ],
      ]),
    );
  }

  // ─── Khối: lương chính ─────────────────────────────────────────

  Widget _mainSection() {
    final k = _d.kind;
    return SettingsSection(
      title: 'Lương chính',
      subtitle: 'Cách trả lương và mức lương',
      icon: Icons.payments_outlined,
      children: [
        SettingsTile(
          label: 'Loại lương',
          divider: false,
          control: SettingsSegment<SalaryKind>(
            value: k,
            options: [for (final x in const [SalaryKind.monthly, SalaryKind.daily, SalaryKind.shift, SalaryKind.hourly]) (x, switch (x) { SalaryKind.monthly => 'Tháng', SalaryKind.daily => 'Ngày', SalaryKind.shift => 'Ca', SalaryKind.hourly => 'Giờ' })],
            onChanged: widget.canEdit
                ? (v) => setState(() {
                      _d.kind = v;
                      if (!_d.insuranceChoices.contains(_d.insurance)) _d.insurance = InsuranceKind.none;
                    })
                : (_) {},
          ),
        ),
        if (k == SalaryKind.monthly) ...[
          SettingsTile(label: 'Lương cơ bản', help: 'Dùng tính BHXH, ngày công', control: _moneyField('base', _d.base, (v) => _d.base = v)),
          SettingsTile(
            label: 'Lương hoàn thành',
            help: 'Phần thưởng theo công, trả khi đủ công chuẩn',
            control: _moneyField('completion', _d.completion, (v) => _d.completion = v),
          ),
        ],
        if (k == SalaryKind.daily) SettingsTile(label: 'Lương một ngày công', control: _moneyField('daily', _d.daily, (v) => _d.daily = v)),
        if (k == SalaryKind.hourly) SettingsTile(label: 'Lương một giờ', control: _moneyField('base', _d.base, (v) => _d.base = v)),
        if (k == SalaryKind.shift) ...[
          SettingsTile(
            label: 'Cách tính',
            control: SettingsSegment<int>(
              value: _d.shiftType,
              options: const [(0, 'Cố định mỗi ca'), (1, 'Theo bậc lương ca')],
              onChanged: widget.canEdit ? (v) => setState(() => _d.shiftType = v) : (_) {},
            ),
          ),
          if (_d.shiftType == 0)
            SettingsTile(label: 'Tiền lương mỗi ca', control: _moneyField('perShift', _d.perShift, (v) => _d.perShift = v))
          else
            const SettingsNote('Mức lương từng ca lấy theo «Bậc lương ca» trong Ca làm việc.', icon: Icons.info_outline_rounded),
        ],
      ],
    );
  }

  // ─── Khối: tăng ca ─────────────────────────────────────────────

  Widget _otSection() {
    final w = _c.otRate('overtimeRate', 1.5);
    final e = _c.otRate('weekendRate', 2.0);
    final h = _c.otRate('holidayRate', 3.0);
    String r(double v) => settingsNum(v);
    final lawUsed = _d.hourlyOtType == 1 || (_d.kind != SalaryKind.hourly && _d.holidayOtType == 1);
    return SettingsSection(
      title: 'Tăng ca',
      subtitle: 'Làm thêm giờ và đi làm ngày nghỉ',
      icon: Icons.more_time_rounded,
      children: [
        SettingsTile(
          label: 'Làm thêm giờ',
          divider: false,
          control: SettingsSegment<int>(
            value: _d.hourlyOtType,
            options: const [(1, 'Theo luật'), (0, 'Cố định'), (2, 'Không tính')],
            onChanged: widget.canEdit ? (v) => setState(() => _d.hourlyOtType = v) : (_) {},
          ),
        ),
        if (_d.hourlyOtType == 0) SettingsTile(label: 'Tiền một giờ tăng ca', control: _moneyField('otFixed', _d.hourlyOtFixed, (v) => _d.hourlyOtFixed = v)),
        if (_d.hourlyOtType == 1 && _d.kind == SalaryKind.monthly)
          SettingsTile(
            label: 'Đơn giá giờ tính theo',
            help: 'Mức chọn ÷ công chuẩn ÷ giờ một công, rồi nhân hệ số',
            control: DropdownButton<String>(
              value: _d.otBase,
              onChanged: widget.canEdit ? (v) => setState(() => _d.otBase = v ?? OvertimeHourlyBaseModes.base) : null,
              items: [
                DropdownMenuItem(value: OvertimeHourlyBaseModes.base, child: Text(tr('Lương cơ bản'))),
                DropdownMenuItem(value: OvertimeHourlyBaseModes.completion, child: Text(tr('Lương hoàn thành'))),
                DropdownMenuItem(value: OvertimeHourlyBaseModes.basePlusCompletion, child: Text(tr('Cơ bản + hoàn thành'))),
              ],
            ),
          ),
        if (_d.kind != SalaryKind.hourly) ...[
          SettingsTile(
            label: 'Đi làm ngày nghỉ',
            control: SettingsSegment<int>(
              value: _d.holidayOtType,
              options: const [(1, 'Theo luật'), (0, 'Cố định ngày')],
              onChanged: widget.canEdit ? (v) => setState(() => _d.holidayOtType = v) : (_) {},
            ),
          ),
          if (_d.holidayOtType == 0)
            SettingsTile(label: 'Tiền công một ngày nghỉ đi làm', control: _moneyField('holidayDaily', _d.holidayOtDaily, (v) => _d.holidayOtDaily = v)),
          SettingsTile(
            label: 'Ngày nghỉ chỉ tính giờ tăng ca',
            help: _d.restDayOtHoursOnly ? 'Đi làm ngày nghỉ: tính giờ tăng ca, không cộng công' : 'Đi làm ngày nghỉ: vẫn cộng công',
            control: Switch(value: _d.restDayOtHoursOnly, onChanged: widget.canEdit ? (v) => setState(() => _d.restDayOtHoursOnly = v) : null),
          ),
          SettingsTile(
            label: 'Tính đi trễ / về sớm ngày nghỉ',
            control: Switch(value: _d.lateEarlyOnRestDayOt, onChanged: widget.canEdit ? (v) => setState(() => _d.lateEarlyOnRestDayOt = v) : null),
          ),
        ],
        if (lawUsed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: Text(tr('Hệ số cửa hàng: ngày thường ×${r(w)} · ngày nghỉ ×${r(e)} · lễ ×${r(h)}'), style: SboxType.smallStyle()),
              ),
              if (widget.onEditStoreRates != null)
                TextButton(onPressed: widget.onEditStoreRates, child: Text(tr('Sửa hệ số'))),
            ]),
          ),
      ],
    );
  }

  // ─── Khối: bảo hiểm ────────────────────────────────────────────

  Widget _insuranceSection() {
    final sal = _d.insuranceSalary(_c.insurance);
    final raw = _d.insuranceSalaryRaw(_c.insurance);
    return SettingsSection(
      title: 'Bảo hiểm xã hội',
      subtitle: 'Mức lương làm căn cứ đóng BHXH, BHYT, BHTN',
      icon: Icons.health_and_safety_outlined,
      children: [
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in _d.insuranceChoices)
            ChoiceChip(
              label: Text(tr(i.label)),
              selected: _d.insurance == i,
              onSelected: widget.canEdit ? (_) => setState(() => _d.insurance = i) : null,
            ),
        ]),
        if (_d.insurance == InsuranceKind.custom)
          SettingsTile(label: 'Mức lương đóng BHXH', control: _moneyField('insCustom', _d.insuranceCustom, (v) => _d.insuranceCustom = v)),
        if (_d.insurance != InsuranceKind.none) ...[
          const SizedBox(height: 12),
          SettingsNote(
            'Lương đóng: ${money(sal)}${raw > sal ? ' (áp trần)' : ''} · nhân viên đóng 10,5%: ${money(sal * 0.105)}',
            icon: Icons.info_outline_rounded,
            tone: SboxTone.neutral,
          ),
        ],
      ],
    );
  }

  // ─── Khối: ngày công & chấm công ───────────────────────────────

  Widget _workSection() {
    final names = _c.shiftNames;
    final unknown = _d.shifts.where((s) => !names.contains(s)).toList();
    return SettingsSection(
      title: 'Ngày công và chấm công',
      subtitle: 'Ngày nghỉ hưởng lương, cách chấm, ca làm việc',
      icon: Icons.event_available_outlined,
      children: [
        SettingsTile(
          label: 'Ngày nghỉ hưởng lương',
          divider: false,
          control: DropdownButton<String>(
            value: _d.paidLeave,
            onChanged: widget.canEdit ? (v) => setState(() => _d.paidLeave = v ?? 'sunday') : null,
            items: [for (final o in paidLeaveOptions) DropdownMenuItem(value: o.$1, child: Text(tr(o.$2)))],
          ),
        ),
        const Divider(height: 24),
        Text(tr('Cách chấm công'), style: SboxType.bodyStrong()),
        const SizedBox(height: 6),
        for (final o in attendanceOptions)
          _Opt(
            title: o.$2,
            subtitle: o.$3,
            selected: _d.attendance == o.$1,
            onTap: widget.canEdit ? () => setState(() => _d.attendance = o.$1) : null,
          ),
        const Divider(height: 24),
        Text(tr('Ca làm việc'), style: SboxType.bodyStrong()),
        Text(tr('Để trống = làm mọi ca theo lịch phân ca.'), style: SboxType.captionStyle()),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in names)
            FilterChip(
              label: Text(s),
              selected: _d.shifts.contains(s),
              onSelected: widget.canEdit ? (v) => setState(() => v ? _d.shifts.add(s) : _d.shifts.remove(s)) : null,
            ),
          for (final s in unknown)
            InputChip(
              label: Text(tr('$s (ca đã xóa / đổi tên)')),
              backgroundColor: SboxColors.warningSoft,
              onDeleted: widget.canEdit ? () => setState(() => _d.shifts.remove(s)) : null,
            ),
          if (names.isEmpty && unknown.isEmpty) Text(tr('Chưa có ca làm việc nào.'), style: SboxType.smallStyle()),
        ]),
        const Divider(height: 24),
        SettingsTile(
          label: 'Số giờ một công',
          help: 'Tổng giờ các ca trong ngày tính là 1 công',
          divider: false,
          control: SizedBox(
            width: 110,
            child: TextField(
              controller: _hours,
              enabled: widget.canEdit,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(isDense: true, suffixText: tr('giờ'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              onChanged: (v) => setState(() => _d.hoursPerDay = double.tryParse(v.replaceAll(',', '.')) ?? 0),
            ),
          ),
        ),
        SettingsTile(
          label: 'Công chuẩn tháng',
          help: _d.fixedStdDays ? 'Đơn giá ngày = lương tháng ÷ số công cố định' : 'Số ngày trong tháng trừ ngày nghỉ hưởng lương',
          control: SettingsSegment<bool>(
            value: _d.fixedStdDays,
            options: const [(false, 'Theo tháng'), (true, 'Cố định')],
            onChanged: widget.canEdit ? (v) => setState(() => _d.fixedStdDays = v) : (_) {},
          ),
        ),
        if (_d.fixedStdDays) ...[
          SettingsTile(
            label: 'Số công cố định',
            control: SizedBox(
              width: 110,
              child: TextField(
                controller: _stdDays,
                enabled: widget.canEdit,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(isDense: true, suffixText: tr('công'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                onChanged: (v) => setState(() => _d.stdDays = int.tryParse(v) ?? 0),
              ),
            ),
          ),
          SettingsTile(
            label: 'Trừ lương khi thiếu công',
            control: Switch(value: _d.deductBelowStd, onChanged: widget.canEdit ? (v) => setState(() => _d.deductBelowStd = v) : null),
          ),
          SettingsTile(
            label: 'Cộng lương khi vượt công',
            control: Switch(value: _d.addAboveStd, onChanged: widget.canEdit ? (v) => setState(() => _d.addAboveStd = v) : null),
          ),
        ],
      ],
    );
  }

  // ─── Khối: phụ cấp ─────────────────────────────────────────────

  Widget _allowanceSection() {
    final fixed = _c.allowancesOf(_e, 0);
    final daily = _c.allowancesOf(_e, 1);
    Widget row(Map<String, dynamic> a, String unit) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 18, color: SboxColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text('${a['name'] ?? ''}', style: SboxType.bodyStyle())),
            Text('${money((a['amount'] as num?) ?? 0)}$unit', style: SboxType.bodyStrong()),
          ]),
        );
    return SettingsSection(
      title: 'Phụ cấp',
      subtitle: 'Gán ở mục Phụ cấp — áp dụng cho nhiều nhân viên cùng lúc',
      icon: Icons.card_giftcard_outlined,
      trailing: TextButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AllowanceSettingsScreen())),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: Text(tr('Quản lý phụ cấp')),
      ),
      children: [
        if (fixed.isEmpty && daily.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Nhân viên chưa được gán phụ cấp nào.'), style: SboxType.smallStyle())),
        for (final a in fixed) row(a, '/tháng'),
        for (final a in daily) row(a, '/ngày'),
      ],
    );
  }

  // ─── Khối: lương đi đường ──────────────────────────────────────

  Widget _travelSection() {
    final on = _d.travel != TravelSalaryMode.off;
    final days = settingsNum(_c.stdDays);
    final hours = settingsNum(_c.stdHours);
    return SettingsSection(
      title: 'Lương đi đường',
      subtitle: 'Trả cho giờ di chuyển công tác đã duyệt trên ứng dụng',
      icon: Icons.directions_car_outlined,
      trailing: Switch(
        value: on,
        onChanged: widget.canEdit ? (v) => setState(() => _d.travel = v ? TravelSalaryMode.basePer8h : TravelSalaryMode.off) : null,
      ),
      children: [
        if (on) ...[
          const SizedBox(height: 4),
          _Opt(title: 'Lương cơ bản ÷ $days công ÷ $hours giờ', selected: _d.travel == TravelSalaryMode.basePer8h, onTap: widget.canEdit ? () => setState(() => _d.travel = TravelSalaryMode.basePer8h) : null),
          _Opt(title: 'Lương hoàn thành ÷ $days công ÷ $hours giờ', selected: _d.travel == TravelSalaryMode.completionPer8h, onTap: widget.canEdit ? () => setState(() => _d.travel = TravelSalaryMode.completionPer8h) : null),
          _Opt(title: '(Cơ bản + hoàn thành) ÷ $days công ÷ $hours giờ', selected: _d.travel == TravelSalaryMode.basePlusCompletionPer8h, onTap: widget.canEdit ? () => setState(() => _d.travel = TravelSalaryMode.basePlusCompletionPer8h) : null),
          _Opt(title: 'Đơn giá cố định mỗi giờ', selected: _d.travel == TravelSalaryMode.fixed, onTap: widget.canEdit ? () => setState(() => _d.travel = TravelSalaryMode.fixed) : null),
          if (_d.travel == TravelSalaryMode.fixed)
            SettingsTile(label: 'Đơn giá một giờ đi đường', control: _moneyField('travel', _d.travelFixed, (v) => _d.travelFixed = v)),
        ],
      ],
    );
  }

  // ─── Khối: phép năm (lương tháng) ──────────────────────────────

  Widget _leaveSection() => SettingsSection(
        title: 'Nghỉ phép',
        subtitle: 'Phép năm chuẩn của nhân viên — thâm niên, tháng làm việc, chuyển phép tính tự động (Thiết lập › Phép năm)',
        icon: Icons.beach_access_outlined,
        children: [
          SettingsTile(label: 'Phép năm có lương', divider: false, control: _intField(_leave, (v) => _d.paidLeaveDays = v)),
          SettingsTile(label: 'Nghỉ không lương tối đa', control: _intField(_unpaid, (v) => _d.unpaidLeaveDays = v)),
        ],
      );

  Widget _intField(TextEditingController c, ValueChanged<int> on) => SizedBox(
        width: 150,
        child: TextField(
          controller: c,
          enabled: widget.canEdit,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(isDense: true, suffixText: tr('ngày/năm'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) => setState(() => on(int.tryParse(v) ?? 0)),
        ),
      );
}

/// Một lựa chọn kiểu radio (không dùng RadioListTile groupValue đã lỗi thời).
class _Opt extends StatelessWidget {
  const _Opt({required this.title, this.subtitle, required this.selected, this.onTap});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20, color: selected ? SboxColors.brand600 : SboxColors.slate400),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: selected ? SboxType.bodyStrong() : SboxType.bodyStyle()),
                if (subtitle != null && subtitle!.isNotEmpty) Text(tr(subtitle!), style: SboxType.captionStyle()),
              ]),
            ),
          ]),
        ),
      );
}
