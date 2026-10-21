import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_sell_industry.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/number_formatter.dart';
import 'pos_theme.dart';

/// Thiết lập dịch vụ tính giờ (karaoke / bi-a / phòng giờ) — bố cục giống POS365 «Thêm mới hàng hóa»:
/// 1. «Số lượng tính theo thời gian sử dụng?»
/// 2. Giá bán + «Giá bán được thiết lập cho từng block?» + «Block tính thời gian (phút)» (mặc định 15)
/// 3. «Số block giờ đầu tiên» + «Giá cho N block giờ đầu tiên» (trống = không dùng)
/// 4. «Thiết lập khung giờ đặc biệt»: từ giờ – đến giờ, tăng / giảm theo % hoặc theo số tiền
/// 5. Tùy chọn nâng cao (ít dùng) + bảng xem trước.
///
/// Lưu xuống các trường sẵn có của PosProduct:
/// - Không tích «từng block» → PerHour (giá 1 giờ, làm tròn theo block); tích → PerBlock (giá 1 block).
/// - Block → BillRoundMinutes; N block đầu → OpeningMinutes = N × block; giá N block → OpeningFee.
/// - Khung giờ → TimeSurchargesJson.
class PosTimedServiceSetup extends StatefulWidget {
  const PosTimedServiceSetup({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.priceCtrl,
    required this.blockCtrl,
    required this.openingFeeCtrl,
    required this.openingMinutesCtrl,
    required this.graceCtrl,
    required this.minBillCtrl,
    required this.roundAfterCtrl,
    required this.timeSurchargesJson,
    required this.onTimeSurchargesChanged,
    this.allowDayMode = false,
  });

  final PosServiceBillingMode mode;
  final ValueChanged<PosServiceBillingMode> onModeChanged;
  final TextEditingController priceCtrl;
  final TextEditingController blockCtrl;
  final TextEditingController openingFeeCtrl;
  final TextEditingController openingMinutesCtrl;
  final TextEditingController graceCtrl;
  final TextEditingController minBillCtrl;
  final TextEditingController roundAfterCtrl;
  final String? timeSurchargesJson;
  final ValueChanged<String?> onTimeSurchargesChanged;

  /// Khách sạn: cho chọn «Giá tính theo ngày / đêm».
  final bool allowDayMode;

  static const defaultBlockMinutes = 15;

  @override
  State<PosTimedServiceSetup> createState() => _PosTimedServiceSetupState();
}

class _RuleRow {
  _RuleRow({String from = '', String to = '', this.increase = true, String value = '', this.isPercent = true})
      : fromCtrl = TextEditingController(text: from),
        toCtrl = TextEditingController(text: to),
        valueCtrl = TextEditingController(text: value);

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final TextEditingController valueCtrl;
  bool increase;
  bool isPercent;

  void dispose() {
    fromCtrl.dispose();
    toCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _PosTimedServiceSetupState extends State<PosTimedServiceSetup> {
  static final _money = NumberFormat('#,###', 'vi_VN');
  late final TextEditingController _firstBlocksCtrl;
  final List<_RuleRow> _rules = [];

  bool get _timed => widget.mode.isTimed;
  bool get _perBlock => widget.mode == PosServiceBillingMode.perBlock;
  bool get _perDay => widget.mode == PosServiceBillingMode.perDay;

  int get _block {
    final v = int.tryParse(widget.blockCtrl.text.trim());
    return v != null && v > 0 ? v : PosTimedServiceSetup.defaultBlockMinutes;
  }

  static double _num(String raw) => double.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  static String _fmtMoney(num v) => v <= 0 ? '' : _money.format(v.round());
  static String _fmtCount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');

  @override
  void initState() {
    super.initState();
    final om = int.tryParse(widget.openingMinutesCtrl.text.trim()) ?? 0;
    final hasFirst = om > 0 || _num(widget.openingFeeCtrl.text) > 0;
    _firstBlocksCtrl = TextEditingController(text: hasFirst ? _fmtCount(om / _block) : '');
    for (final r in PosServiceBillingCalc.parseTimeSurcharges(widget.timeSurchargesJson)) {
      _rules.add(_RuleRow(
        from: PosTimeSurchargeRule.hm(r.fromMinute),
        to: PosTimeSurchargeRule.hm(r.toMinute),
        increase: r.value >= 0,
        value: r.isPercent ? _fmtCount(r.value.abs()) : _fmtMoney(r.value.abs()),
        isPercent: r.isPercent,
      ));
    }
  }

  @override
  void dispose() {
    _firstBlocksCtrl.dispose();
    for (final r in _rules) {
      r.dispose();
    }
    super.dispose();
  }

  // ─── Đồng bộ xuống controller của form ───────────────────────────

  void _syncOpeningMinutes() {
    final n = double.tryParse(_firstBlocksCtrl.text.trim().replaceAll(',', '.'));
    widget.openingMinutesCtrl.text = n == null || n <= 0 ? '' : '${(n * _block).round()}';
  }

  void _emitRules() {
    final rules = <PosTimeSurchargeRule>[];
    for (final r in _rules) {
      final from = _hm(r.fromCtrl.text);
      final to = _hm(r.toCtrl.text);
      final v = r.isPercent
          ? double.tryParse(r.valueCtrl.text.trim().replaceAll(',', '.')) ?? 0
          : _num(r.valueCtrl.text);
      if (from == null || to == null || v == 0) continue;
      rules.add(PosTimeSurchargeRule(
          fromMinute: from, toMinute: to, isPercent: r.isPercent, value: r.increase ? v : -v));
    }
    widget.onTimeSurchargesChanged(PosServiceBillingCalc.encodeTimeSurcharges(rules));
  }

  static int? _hm(String raw) {
    final m = RegExp(r'^\s*(\d{1,2})(?:[:hH.](\d{1,2}))?\s*$').firstMatch(raw);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h > 24 || min > 59) return null;
    return (h * 60 + min) % 1440;
  }

  void _setTimed(bool on) {
    if (on) {
      if (widget.blockCtrl.text.trim().isEmpty) {
        widget.blockCtrl.text = '${PosTimedServiceSetup.defaultBlockMinutes}';
      }
      widget.onModeChanged(PosServiceBillingMode.perHour);
    } else {
      widget.onModeChanged(PosServiceBillingMode.flat);
    }
  }

  /// Đổi «giá theo giờ» ↔ «giá theo block» thì quy đổi giá luôn, tránh 60.000đ/giờ thành 60.000đ/block.
  void _setPerBlock(bool on) {
    final price = _num(widget.priceCtrl.text);
    if (price > 0) {
      final unitFrom = _perBlock ? _block : (widget.mode == PosServiceBillingMode.perMinute ? 1 : 60);
      final unitTo = on ? _block : 60;
      widget.priceCtrl.text = _fmtMoney(price * unitTo / unitFrom);
    }
    if (widget.blockCtrl.text.trim().isEmpty) {
      widget.blockCtrl.text = '${PosTimedServiceSetup.defaultBlockMinutes}';
    }
    widget.onModeChanged(on ? PosServiceBillingMode.perBlock : PosServiceBillingMode.perHour);
  }

  // ─── Giao diện ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 640;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _check(
          value: _timed,
          label: 'Số lượng tính theo thời gian sử dụng?',
          help: 'Karaoke, bi-a, phòng giờ: bấm Bắt đầu khi mở bàn, máy tự đếm giờ và tính tiền.',
          strong: true,
          onChanged: _setTimed,
        ),
        if (_timed) ...[
          const SizedBox(height: 10),
          _priceRow(wide),
          _rateHint(),
          if (!_perDay) ...[
            const SizedBox(height: 4),
            _check(
              value: _perBlock,
              label: 'Giá bán được thiết lập cho từng block?',
              help: _perBlock
                  ? 'Giá bán là tiền 1 block. Vào block mới là tính thêm 1 block.'
                  : 'Giá bán là tiền 1 giờ; thời gian làm tròn lên theo block.',
              onChanged: _setPerBlock,
            ),
            const SizedBox(height: 8),
            _field(
              ctrl: widget.blockCtrl,
              label: 'Block tính thời gian sử dụng dịch vụ (phút)',
              hint: 'VD 15',
              digitsOnly: true,
              onChanged: (_) => setState(_syncOpeningMinutes),
            ),
            const SizedBox(height: 12),
            _firstBlocksBox(wide),
            const SizedBox(height: 12),
            _specialHours(wide),
          ],
          _advanced(),
          const SizedBox(height: 8),
          _preview(),
        ],
      ],
    );
  }

  Widget _check({
    required bool value,
    required String label,
    String? help,
    bool strong = false,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => setState(() => onChanged(!value)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 28,
              child: Checkbox(value: value, onChanged: (v) => setState(() => onChanged(v == true))),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(tr(label),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                        color: strong && value ? SboxColors.danger : SboxColors.slate800,
                      )),
                  if (help != null)
                    Text(tr(help), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    String? hint,
    bool money = false,
    bool digitsOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textAlign: money ? TextAlign.right : TextAlign.start,
      inputFormatters: money
          ? [ThousandSeparatorFormatter()]
          : digitsOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
      onChanged: onChanged ?? (_) => setState(() {}),
      decoration: PosTheme.inputDecoration(label: label, hint: hint),
    );
  }

  String get _priceUnitWord => switch (widget.mode) {
        PosServiceBillingMode.perBlock => 'block ($_block phút)',
        PosServiceBillingMode.perMinute => 'phút',
        PosServiceBillingMode.perDay => 'ngày / đêm',
        _ => 'giờ',
      };

  Widget _priceRow(bool wide) {
    final price = _field(
      ctrl: widget.priceCtrl,
      label: 'Giá bán (1 $_priceUnitWord)',
      hint: _perBlock ? 'VD 15.000' : 'VD 60.000',
      money: true,
    );
    if (_perBlock) return price;
    // Giá theo giờ là mặc định; phút / ngày (khách sạn) chọn ở đây cho gọn.
    final unit = DropdownButtonFormField<PosServiceBillingMode>(
      value: widget.mode == PosServiceBillingMode.perMinute || _perDay
          ? widget.mode
          : PosServiceBillingMode.perHour,
      isExpanded: true,
      decoration: PosTheme.inputDecoration(label: 'Giá tính theo'),
      items: [
        DropdownMenuItem(value: PosServiceBillingMode.perHour, child: Text(tr('Giờ'))),
        DropdownMenuItem(value: PosServiceBillingMode.perMinute, child: Text(tr('Phút'))),
        if (widget.allowDayMode || _perDay)
          DropdownMenuItem(value: PosServiceBillingMode.perDay, child: Text(tr('Ngày / đêm'))),
      ],
      onChanged: (v) {
        if (v == null || v == widget.mode) return;
        if (v == PosServiceBillingMode.perDay) {
          if ((int.tryParse(widget.blockCtrl.text.trim()) ?? 0) < 60) widget.blockCtrl.text = '1440';
          if (widget.minBillCtrl.text.trim().isEmpty) widget.minBillCtrl.text = '1440';
        } else if (_perDay) {
          widget.blockCtrl.text = '${PosTimedServiceSetup.defaultBlockMinutes}';
          if (widget.minBillCtrl.text.trim() == '1440') widget.minBillCtrl.text = '';
        }
        setState(() => widget.onModeChanged(v));
      },
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: price),
        const SizedBox(width: 12),
        Expanded(flex: wide ? 2 : 3, child: unit),
      ],
    );
  }

  Widget _rateHint() {
    final price = _num(widget.priceCtrl.text);
    if (price <= 0) return const SizedBox(height: 4);
    String m(num v) => '${_money.format(v.round())}đ';
    final text = switch (widget.mode) {
      PosServiceBillingMode.perBlock => '1 block $_block phút = ${m(price)}, tức 1 giờ = ${m(price * 60 / _block)}',
      PosServiceBillingMode.perHour => '1 giờ = ${m(price)}, tức 1 block $_block phút = ${m(price * _block / 60)}',
      PosServiceBillingMode.perMinute => '1 phút = ${m(price)}, tức 1 giờ = ${m(price * 60)}',
      _ => '1 ngày / đêm = ${m(price)}',
    };
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(8)),
      child: Text(tr(text),
          style: const TextStyle(fontSize: 12.5, color: SboxColors.brand800, fontWeight: FontWeight.w600)),
    );
  }

  Widget _firstBlocksBox(bool wide) {
    final n = _firstBlocksCtrl.text.trim().isEmpty ? '0' : _firstBlocksCtrl.text.trim();
    final minutes = int.tryParse(widget.openingMinutesCtrl.text.trim()) ?? 0;
    final count = _field(
      ctrl: _firstBlocksCtrl,
      label: 'Số block giờ đầu tiên',
      hint: 'VD 4 (= 1 giờ)',
      digitsOnly: true,
      onChanged: (_) => setState(_syncOpeningMinutes),
    );
    final price = _field(
      ctrl: widget.openingFeeCtrl,
      label: 'Giá cho $n block giờ đầu tiên',
      hint: 'VD 50.000',
      money: true,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SboxColors.successSoft.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SboxColors.success.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: count),
                  const SizedBox(width: 12),
                  Expanded(child: price),
                ])
              : Column(children: [count, const SizedBox(height: 10), price]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sentiment_satisfied_alt, size: 16, color: SboxColors.successText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(minutes > 0
                      ? 'Giờ đầu: $minutes phút đầu tính trọn giá trên, sau đó mới tính theo giá bán. '
                          'Để trống 2 ô này nếu quán không tính giá riêng cho giờ đầu.'
                      : 'Để trống 2 ô này nếu quán không tính giá riêng cho giờ đầu. '
                          '0 block + có giá = phí mở bàn, cộng ngay khi mở.'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.successText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specialHours(bool wide) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SboxColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: const BoxDecoration(
              color: SboxColors.slate50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (wide) Expanded(child: _specialHoursTitle()) else _specialHoursTitle(),
                TextButton.icon(
                  onPressed: () => setState(() => _rules.add(_RuleRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Thêm khung giờ')),
                ),
              ],
            ),
          ),
          if (_rules.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('Chưa có khung giờ đặc biệt — cả ngày tính một giá.'),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
            ),
          for (var i = 0; i < _rules.length; i++) _ruleRow(i, wide),
        ],
      ),
    );
  }

  Widget _specialHoursTitle() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Thiết lập khung giờ đặc biệt'),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand700)),
                    Text(tr('Giờ cao điểm tăng giá, giờ sáng giảm giá… Phần thời gian rơi vào khung nào thì cộng / trừ theo khung đó.'),
                        style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                  ]);

  Widget _ruleRow(int i, bool wide) {
    final r = _rules[i];
    Future<void> pick(TextEditingController c) async {
      final cur = _hm(c.text);
      final t = await showTimePicker(
        context: context,
        initialTime: cur == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (t == null) return;
      c.text = PosTimeSurchargeRule.hm(t.hour * 60 + t.minute);
      setState(_emitRules);
    }

    Widget time(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: TextInputType.datetime,
          onChanged: (_) => _emitRules(),
          decoration: PosTheme.inputDecoration(label: label, hint: '18:00').copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.schedule, size: 18),
              tooltip: tr('Chọn giờ'),
              onPressed: () => pick(c),
            ),
          ),
        );

    Widget seg(List<(String, bool)> opts, bool value, ValueChanged<bool> onPick) => SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final o in opts) ButtonSegment(value: o.$2, label: Text(tr(o.$1)))],
          selected: {value},
          onSelectionChanged: (s) => setState(() {
            onPick(s.first);
            _emitRules();
          }),
        );

    final value = TextField(
      controller: r.valueCtrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      inputFormatters: r.isPercent ? null : [ThousandSeparatorFormatter()],
      onChanged: (_) => _emitRules(),
      decoration: PosTheme.inputDecoration(
        label: r.isPercent ? 'Mức (%)' : 'Số tiền / $_priceUnitWord',
        hint: r.isPercent ? '20' : '10.000',
      ),
    );
    final remove = IconButton(
      tooltip: tr('Xóa khung giờ'),
      icon: const Icon(Icons.delete_outline, color: SboxColors.danger),
      onPressed: () => setState(() {
        _rules.removeAt(i).dispose();
        _emitRules();
      }),
    );
    final kind = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      seg([('Tăng', true), ('Giảm', false)], r.increase, (v) => r.increase = v),
      seg([('%', true), ('Số tiền', false)], r.isPercent, (v) {
        r.isPercent = v;
        r.valueCtrl.clear();
      }),
    ]);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: SboxColors.divider))),
      child: wide
          ? Row(children: [
              SizedBox(width: 120, child: time(r.fromCtrl, 'Từ')),
              const SizedBox(width: 8),
              SizedBox(width: 120, child: time(r.toCtrl, 'Đến')),
              const SizedBox(width: 10),
              kind,
              const SizedBox(width: 10),
              Expanded(child: value),
              remove,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: time(r.fromCtrl, 'Từ')),
                const SizedBox(width: 8),
                Expanded(child: time(r.toCtrl, 'Đến')),
                remove,
              ]),
              const SizedBox(height: 8),
              kind,
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(right: 8), child: value),
            ]),
    );
  }

  Widget _advanced() {
    final anySet = [widget.graceCtrl, widget.minBillCtrl, widget.roundAfterCtrl]
        .any((c) => c.text.trim().isNotEmpty);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: anySet,
        title: Text(tr('Tùy chọn nâng cao (ít dùng)'),
            style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
        children: [
          Row(children: [
            Expanded(
              child: _field(
                  ctrl: widget.graceCtrl, label: 'Phút đầu miễn phí', hint: 'VD 5', digitsOnly: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                  ctrl: widget.minBillCtrl, label: 'Tính tối thiểu (phút)', hint: 'VD 60', digitsOnly: true),
            ),
          ]),
          const SizedBox(height: 12),
          _field(
            ctrl: widget.roundAfterCtrl,
            label: 'Chỉ làm tròn block khi dùng quá (phút)',
            hint: 'Trống = luôn làm tròn',
            digitsOnly: true,
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final price = _num(widget.priceCtrl.text);
    final rows = PosServiceBillingCalc.preview(
      mode: widget.mode,
      unitPrice: price,
      minBillMinutes: int.tryParse(widget.minBillCtrl.text.trim()),
      billRoundMinutes: int.tryParse(widget.blockCtrl.text.trim()),
      graceMinutes: int.tryParse(widget.graceCtrl.text.trim()),
      roundAfterMinutes: int.tryParse(widget.roundAfterCtrl.text.trim()),
      openingFee: _num(widget.openingFeeCtrl.text),
      openingMinutes: int.tryParse(widget.openingMinutesCtrl.text.trim()),
      elapsedSamples: _perDay ? const [60, 600, 1440, 1500, 2880] : const [10, 15, 16, 30, 45, 60, 61, 90, 120, 180],
    );
    final unit = PosServiceBillingCalc.timedUnitName(widget.mode).toLowerCase();
    const head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.slate500);
    String dur(int m) => m < 60 ? '$m phút' : '${m ~/ 60} giờ${m % 60 > 0 ? ' ${m % 60} phút' : ''}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Xem trước: khách dùng bao lâu thì trả bao nhiêu'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (_rules.isNotEmpty)
            Text(tr('(chưa gồm khung giờ đặc biệt — phụ thuộc giờ khách vào)'),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(flex: 3, child: Text(tr('Khách dùng'), style: head)),
            Expanded(flex: 3, child: Text(tr('Số lượng trên hóa đơn'), style: head)),
            Expanded(flex: 3, child: Text(tr('Thành tiền'), textAlign: TextAlign.right, style: head)),
          ]),
          const Divider(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(flex: 3, child: Text(tr(dur(r.elapsed)), style: const TextStyle(fontSize: 12.5))),
                Expanded(
                  flex: 3,
                  child: Text(
                    tr(r.qty <= 0 && _num(widget.openingFeeCtrl.text) > 0
                        ? 'giờ đầu'
                        : '${_fmtCount(r.qty).replaceAll('.', ',')} $unit${r.qty > 0 && _num(widget.openingFeeCtrl.text) > 0 ? ' + giờ đầu' : ''}'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text('${_money.format(r.total.round())}đ',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
