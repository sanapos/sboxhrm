import 'package:flutter/material.dart';
import 'package:payroll_engine/payroll/payroll_policy.dart';

import '../../l10n/app_tr.dart';
import '../../widgets/settings/settings_page.dart' show settingsNum;
import '../../widgets/sbox/sbox_ui.dart';

/// Nhãn ngắn của chính sách (nút trên màn Thiết lập lương).
String payrollPolicyBadge(Map<String, dynamic> store) =>
    PayrollPolicy.fromSalarySettings(store).isLaw ? 'Theo luật' : 'Tùy chỉnh';

/// Chính sách tính lương của cửa hàng: «Theo luật» (khóa mức tối thiểu) hoặc «Tùy chỉnh» từng mục.
/// Trả payload lưu `/api/settings/salary` (đã gộp [store]) hoặc null khi hủy.
Future<Map<String, dynamic>?> showPayrollPolicyDialog(BuildContext context, Map<String, dynamic> store) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _PolicyDialog(store: store),
  );
}

class _PolicyDialog extends StatefulWidget {
  const _PolicyDialog({required this.store});
  final Map<String, dynamic> store;

  @override
  State<_PolicyDialog> createState() => _PolicyDialogState();
}

class _PolicyDialogState extends State<_PolicyDialog> {
  late bool _law;
  late PayScope _holiday, _leave, _nightScope;
  late bool _nightOn, _bhxh14;
  late NightBasis _basis;
  late final TextEditingController _nightPct, _otW, _otE, _otH;
  final _lawPct = TextEditingController(text: '30');
  String? _error;

  double _rate(String key, double fb) {
    final v = widget.store[key];
    return v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fb);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.store;
    final law = PayrollPolicy.fromSalarySettings(s).isLaw;
    // Mục tùy chỉnh đọc thẳng giá trị đã lưu (chuyển qua lại «Theo luật» không mất cấu hình riêng).
    final custom = PayrollPolicy.fromSalarySettings({...s, 'payrollPolicyPreset': 'custom'});
    _law = law;
    _holiday = custom.holidayPayScope;
    _leave = custom.paidLeavePayScope;
    _nightScope = custom.nightScope;
    _nightOn = custom.nightPremiumEnabled;
    _bhxh14 = custom.bhxh14DayRule;
    _basis = custom.nightBasis;
    _nightPct = TextEditingController(text: settingsNum(custom.nightPremiumPercent));
    _otW = TextEditingController(text: settingsNum(_rate('overtimeRate', 1.5)));
    _otE = TextEditingController(text: settingsNum(_rate('weekendRate', 2.0)));
    _otH = TextEditingController(text: settingsNum(_rate('holidayRate', 3.0)));
  }

  @override
  void dispose() {
    for (final c in [_nightPct, _otW, _otE, _otH, _lawPct]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final w = _num(_otW), e = _num(_otE), h = _num(_otH), pct = _num(_nightPct);
    if (w == null || e == null || h == null || w < 1 || e < 1 || h < 1 || w > 10 || e > 10 || h > 10) {
      setState(() => _error = 'Hệ số tăng ca phải từ 1 đến 10.');
      return;
    }
    if (_law && (w < 1.5 || e < 2 || h < 3)) {
      setState(() => _error = 'Theo luật: hệ số tăng ca tối thiểu ×1,5 (thường) · ×2 (nghỉ tuần) · ×3 (lễ).');
      return;
    }
    if (!_law && _nightOn && (pct == null || pct < 0 || pct > 300)) {
      setState(() => _error = 'Phụ cấp đêm phải từ 0% đến 300%.');
      return;
    }
    final custom = PayrollPolicy(
      isLaw: _law,
      holidayPayScope: _holiday,
      paidLeavePayScope: _leave,
      nightPremiumEnabled: _nightOn,
      nightPremiumPercent: pct ?? 30,
      nightBasis: _basis,
      nightScope: _nightScope,
      bhxh14DayRule: _bhxh14,
    );
    Navigator.pop(context, {
      ...widget.store,
      'overtimeRate': w,
      'weekendRate': e,
      'holidayRate': h,
      ...custom.toSalarySettings(),
    });
  }

  Widget _section(String title, String legal, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(title), style: SboxType.bodyStrong()),
          const SizedBox(height: 2),
          Text(tr(legal), style: SboxType.captionStyle()),
          const SizedBox(height: 6),
          child,
        ]),
      );

  Widget _scope(PayScope value, ValueChanged<PayScope> onChanged, {List<PayScope>? options, String? label}) => DropdownButtonFormField<PayScope>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label == null ? null : tr(label), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        items: [
          for (final s in options ?? const [PayScope.none, PayScope.monthly, PayScope.monthlyDaily, PayScope.all])
            DropdownMenuItem(value: s, child: Text(tr(s.label), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _law ? null : (v) => v == null ? null : setState(() => onChanged(v)),
      );

  Widget _rateField(String label, String hint, TextEditingController c) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr(label),
            helperText: tr(hint),
            prefixText: '× ',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const law = PayrollPolicy.law;
    final holiday = _law ? law.holidayPayScope : _holiday;
    final leave = _law ? law.paidLeavePayScope : _leave;
    return AlertDialog(
      title: Text(tr('Chính sách tính lương')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, icon: const Icon(Icons.gavel_rounded), label: Text(tr('Theo luật'))),
                ButtonSegment(value: false, icon: const Icon(Icons.tune_rounded), label: Text(tr('Tùy chỉnh'))),
              ],
              selected: {_law},
              onSelectionChanged: (v) => setState(() {
                _law = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              tr(_law
                  ? 'Áp mức tối thiểu theo Bộ luật Lao động 2019 và Luật BHXH. Các mục bên dưới bị khóa; hệ số tăng ca chỉ được cao hơn mức luật.'
                  : 'Cửa hàng tự quyết từng mục (ví dụ nhân viên bán thời gian không trả ngày lễ). Mặc định giữ cách tính trước đây.'),
              style: SboxType.smallStyle(),
            ),
            const SizedBox(height: 14),
            _section('Hệ số tăng ca', 'Điều 98: ngày thường ≥ 150%, ngày nghỉ tuần ≥ 200%, ngày lễ ≥ 300% (chưa kể lương ngày lễ).',
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _rateField('Thường', '≥ 1,5', _otW),
                  const SizedBox(width: 8),
                  _rateField('Nghỉ tuần', '≥ 2', _otE),
                  const SizedBox(width: 8),
                  _rateField('Lễ, Tết', '≥ 3', _otH),
                ])),
            _section('Trả lương ngày lễ', 'Điều 112: nghỉ lễ hưởng nguyên lương. Ngày lễ trùng ngày nghỉ tuần không cộng (cửa hàng xếp nghỉ bù).',
                _scope(holiday, (v) => _holiday = v)),
            _section('Trả lương ngày nghỉ có lương đã duyệt', 'Điều 113, 115: phép năm, việc riêng có lương, nghỉ bù, đơn «vẫn tính công». Nghỉ không lương / ốm BHXH không trả.',
                _scope(leave, (v) => _leave = v)),
            _section(
              'Phụ cấp làm đêm',
              'Điều 98, 106: làm từ 22:00 đến 06:00 được cộng ít nhất 30% đơn giá giờ.',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _law ? true : _nightOn,
                  onChanged: _law ? null : (v) => setState(() => _nightOn = v),
                  title: Text(tr('Có phụ cấp làm đêm')),
                ),
                if (_law || _nightOn) ...[
                  SizedBox(
                    width: 120,
                    child: TextField(
                      // Theo luật: hiện 30% cố định (khóa) — vẫn dùng một controller, không tạo mới mỗi lần vẽ.
                      controller: _law ? _lawPct : _nightPct,
                      enabled: !_law,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('Mức'),
                        suffixText: '%',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<NightBasis>(
                    initialValue: _law ? law.nightBasis : _basis,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Tính theo'), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    items: [
                      for (final b in NightBasis.values)
                        DropdownMenuItem(value: b, child: Text(tr(b.label), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _law ? null : (v) => v == null ? null : setState(() => _basis = v),
                  ),
                  const SizedBox(height: 8),
                  _scope(_law ? law.nightScope : _nightScope, (v) => _nightScope = v,
                      options: const [PayScope.shiftOnly, PayScope.monthly, PayScope.monthlyDaily, PayScope.all], label: 'Áp dụng cho'),
                ],
              ]),
            ),
            _section('BHXH tháng nghỉ dài', 'Luật BHXH: tháng không làm việc và không hưởng lương từ 14 ngày làm việc trở lên thì không đóng BHXH, BHYT, BHTN.',
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _law ? true : _bhxh14,
                  onChanged: _law ? null : (v) => setState(() => _bhxh14 = v),
                  title: Text(tr('Không trừ BHXH tháng có từ 14 ngày không làm, không lương')),
                )),
            if (_error != null)
              Text(tr(_error!), style: SboxType.smallStyle(SboxColors.danger)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _save, child: Text(tr('Lưu chính sách'))),
      ],
    );
  }
}
