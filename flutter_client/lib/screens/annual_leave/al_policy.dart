import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/settings/settings_page.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Chính sách phép năm của cửa hàng (Thiết lập › Phép năm).
class AnnualLeavePolicyScreen extends StatefulWidget {
  const AnnualLeavePolicyScreen({super.key, this.canEditOverride});
  final bool? canEditOverride;

  @override
  State<AnnualLeavePolicyScreen> createState() => _AnnualLeavePolicyScreenState();
}

class _AnnualLeavePolicyScreenState extends State<AnnualLeavePolicyScreen> {
  final _api = ApiService();
  Map<String, dynamic> _p = {};
  String _saved = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _days = TextEditingController();
  final _carryMax = TextEditingController();
  final _std = TextEditingController();

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return p.canEdit('Leave') || p.canEdit('SalarySettings');
    } catch (_) {
      return false;
    }
  }

  static const _defaults = <String, dynamic>{
    'defaultDays': 12,
    'applyTo': 'monthly',
    'seniorityEveryYears': 5,
    'seniorityDays': 1,
    'prorateByMonths': true,
    'prorateCutoffDay': 15,
    'yearEndMode': 'carry',
    'carryMaxDays': 12,
    'carryExpireMonth': 3,
    'payoutBasis': 'base',
    'payoutStandardDays': 26,
    'countWorkingDaysOnly': true,
    'allowNegative': false,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _days.dispose();
    _carryMax.dispose();
    _std.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getAnnualLeavePolicy();
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] is Map) {
      _apply(Map<String, dynamic>.from(r['data'] as Map));
      setState(() => _loading = false);
    } else {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được chính sách phép năm.';
      });
    }
  }

  void _apply(Map<String, dynamic> p) {
    _p = {..._defaults, ...p};
    String n(dynamic v) {
      final d = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
    }

    _days.text = n(_p['defaultDays']);
    _carryMax.text = _p['carryMaxDays'] == null ? '' : n(_p['carryMaxDays']);
    _std.text = n(_p['payoutStandardDays']);
    _saved = jsonEncode(_p);
  }

  bool get _dirty => jsonEncode(_p) != _saved;

  void _set(String k, dynamic v) => setState(() => _p[k] = v);

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _api.saveAnnualLeavePolicy(_p);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true && r['data'] is Map) {
      setState(() => _apply(Map<String, dynamic>.from(r['data'] as Map)));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Đã lưu chính sách phép năm')), behavior: SnackBarBehavior.floating));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(r['message']?.toString() ?? 'Không lưu được')),
        backgroundColor: SboxColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _num(TextEditingController c, String key, {String suffix = 'ngày', bool nullable = false, double width = 120}) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          enabled: _canEdit,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            suffixText: tr(suffix),
            hintText: nullable ? tr('Không giới hạn') : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) {
            final d = double.tryParse(v.replaceAll(',', '.'));
            _set(key, d ?? (nullable ? null : 0));
          },
        ),
      );

  Widget _intDrop(String key, List<(int, String)> opts) => DropdownButton<int>(
        value: (_p[key] as num?)?.toInt() ?? opts.first.$1,
        onChanged: _canEdit ? (v) => _set(key, v) : null,
        items: [for (final o in opts) DropdownMenuItem(value: o.$1, child: Text(tr(o.$2)))],
      );

  @override
  Widget build(BuildContext context) {
    final mode = '${_p['yearEndMode'] ?? 'carry'}';
    final carry = mode == 'carry' || mode == 'carry_payout';
    final pays = mode == 'payout' || mode == 'carry_payout';
    return SettingsPage(
      title: 'Phép năm',
      subtitle: 'Số ngày phép, thâm niên, chuyển phép và tiền phép còn lại',
      icon: Icons.beach_access_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      dirty: _canEdit && _dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: () => setState(() => _apply(jsonDecode(_saved) as Map<String, dynamic>)),
      onResetDefaults: _canEdit
          ? () => setState(() {
                final keep = _saved;
                _apply({..._defaults});
                _saved = keep; // về mặc định = thay đổi chưa lưu
              })
          : null,
      children: [
        SettingsSection(
          title: 'Số ngày được hưởng',
          subtitle: 'Bộ luật Lao động: 12 ngày/năm, cứ đủ 5 năm làm việc thêm 1 ngày',
          icon: Icons.event_available_outlined,
          children: [
            SettingsTile(
              label: 'Phép năm mặc định',
              help: 'Hồ sơ lương tháng ghi số khác thì dùng số trong hồ sơ',
              divider: false,
              control: _num(_days, 'defaultDays'),
            ),
            SettingsTile(
              label: 'Áp dụng cho',
              control: SettingsSegment<String>(
                value: '${_p['applyTo']}',
                options: const [('monthly', 'Lương tháng'), ('all', 'Mọi nhân viên')],
                onChanged: _canEdit ? (v) => _set('applyTo', v) : (_) {},
              ),
            ),
            SettingsTile(
              label: 'Phép thâm niên',
              help: 'Cộng thêm ngày phép theo số năm làm việc',
              control: _intDrop('seniorityEveryYears', const [(0, 'Không cộng'), (3, 'Mỗi 3 năm +1'), (5, 'Mỗi 5 năm +1 (luật)')]),
            ),
            SettingsTile(
              label: 'Vào làm / nghỉ việc giữa năm',
              help: _p['prorateByMonths'] == true
                  ? 'Tính theo số tháng làm việc: (phép năm ÷ 12) × số tháng, lẻ từ 0,5 làm tròn lên'
                  : 'Được hưởng đủ phép cả năm',
              control: Switch(value: _p['prorateByMonths'] == true, onChanged: _canEdit ? (v) => _set('prorateByMonths', v) : null),
            ),
            if (_p['prorateByMonths'] == true)
              SettingsTile(
                label: 'Tháng vào làm được tính nếu vào trước ngày',
                control: _intDrop('prorateCutoffDay', const [(1, 'Ngày 1'), (10, 'Ngày 10'), (15, 'Ngày 15'), (20, 'Ngày 20'), (31, 'Mọi ngày')]),
              ),
          ],
        ),
        SettingsSection(
          title: 'Khi xin nghỉ phép năm',
          subtitle: 'Đơn phép năm được duyệt sẽ tự trừ vào quỹ phép',
          icon: Icons.fact_check_outlined,
          children: [
            SettingsTile(
              label: 'Chỉ trừ ngày làm việc',
              help: _p['countWorkingDaysOnly'] == true
                  ? 'Bỏ Chủ nhật / ngày nghỉ hằng tuần theo hồ sơ lương và ngày lễ trong khoảng nghỉ'
                  : 'Trừ mọi ngày trong khoảng nghỉ (kể cả Chủ nhật, lễ)',
              divider: false,
              control: Switch(value: _p['countWorkingDaysOnly'] == true, onChanged: _canEdit ? (v) => _set('countWorkingDaysOnly', v) : null),
            ),
            SettingsTile(
              label: 'Cho duyệt khi không đủ phép',
              help: _p['allowNegative'] == true ? 'Quỹ phép có thể âm — trừ vào năm sau / lương' : 'Không cho gửi / duyệt đơn vượt số phép còn lại',
              control: Switch(value: _p['allowNegative'] == true, onChanged: _canEdit ? (v) => _set('allowNegative', v) : null),
            ),
          ],
        ),
        SettingsSection(
          title: 'Phép còn lại cuối năm',
          subtitle: 'Áp dụng khi «Chốt phép năm». Người nghỉ việc luôn được trả tiền phép còn lại (Điều 113)',
          icon: Icons.event_repeat_outlined,
          children: [
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in const [
                ('carry', 'Chuyển sang năm sau'),
                ('carry_payout', 'Chuyển tối đa, trả tiền phần dư'),
                ('payout', 'Trả tiền hết'),
                ('none', 'Hủy phép còn lại'),
              ])
                ChoiceChip(label: Text(tr(o.$2)), selected: mode == o.$1, onSelected: _canEdit ? (_) => _set('yearEndMode', o.$1) : null),
            ]),
            if (carry) ...[
              SettingsTile(label: 'Chuyển tối đa', help: 'Để trống = chuyển hết', control: _num(_carryMax, 'carryMaxDays', nullable: true)),
              SettingsTile(
                label: 'Phép chuyển sang phải dùng trước',
                help: 'Quá hạn chưa dùng thì hủy',
                control: _intDrop('carryExpireMonth', [
                  (0, 'Không thời hạn'),
                  for (var m = 1; m <= 12; m++) (m, 'Hết tháng $m'),
                ]),
              ),
            ],
          ],
        ),
        SettingsSection(
          title: 'Tiền phép',
          subtitle: 'Trả cho ngày phép chưa nghỉ (nghỉ việc / cuối năm) — cộng vào bảng lương',
          icon: Icons.payments_outlined,
          children: [
            SettingsTile(
              label: 'Tiền một ngày phép theo',
              divider: false,
              control: SettingsSegment<String>(
                value: '${_p['payoutBasis']}',
                options: const [('base', 'Lương cơ bản'), ('base_completion', 'Cơ bản + hoàn thành')],
                onChanged: _canEdit ? (v) => _set('payoutBasis', v) : (_) {},
              ),
            ),
            SettingsTile(
              label: 'Chia cho số công',
              help: 'Tiền 1 ngày = lương tháng ÷ số công (lương ngày/giờ/ca lấy đơn giá ngày)',
              control: _num(_std, 'payoutStandardDays', suffix: 'công'),
            ),
            if (!pays && !carry)
              const SettingsNote('Đang chọn «Hủy phép còn lại» — chỉ người nghỉ việc được trả tiền phép.', icon: Icons.info_outline_rounded),
          ],
        ),
      ],
    );
  }
}
