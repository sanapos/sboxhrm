import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Mức đóng bảo hiểm của cửa hàng (một bản ghi / cửa hàng).
class InsParams {
  InsParams({
    this.baseSalary = 2340000,
    this.region = const [4960000, 4410000, 3860000, 3450000],
    this.maxSalary = 46800000,
    this.bhxh = (8, 17.5),
    this.bhyt = (1.5, 3),
    this.bhtn = (1, 1),
    this.union = (1, 2),
    this.defaultRegion = 1,
  });

  double baseSalary;
  List<double> region;
  double maxSalary;

  /// (người lao động %, doanh nghiệp %)
  (double, double) bhxh;
  (double, double) bhyt;
  (double, double) bhtn;
  (double, double) union;
  int defaultRegion;

  /// Lương tối thiểu vùng áp dụng từ 01/01/2026 (I–IV).
  static const region2026 = <double>[5310000, 4730000, 4140000, 3700000];

  InsParams copy() => InsParams(
        baseSalary: baseSalary,
        region: [...region],
        maxSalary: maxSalary,
        bhxh: bhxh,
        bhyt: bhyt,
        bhtn: bhtn,
        union: union,
        defaultRegion: defaultRegion,
      );

  static double _d(dynamic v, double f) => v is num ? v.toDouble() : double.tryParse('$v') ?? f;

  factory InsParams.fromJson(Map<String, dynamic> j) {
    final d = InsParams();
    return InsParams(
      baseSalary: _d(j['baseSalary'], d.baseSalary),
      region: [
        _d(j['minSalaryRegion1'], d.region[0]),
        _d(j['minSalaryRegion2'], d.region[1]),
        _d(j['minSalaryRegion3'], d.region[2]),
        _d(j['minSalaryRegion4'], d.region[3]),
      ],
      maxSalary: _d(j['maxInsuranceSalary'], d.maxSalary),
      bhxh: (_d(j['bhxhEmployeeRate'], 8), _d(j['bhxhEmployerRate'], 17.5)),
      bhyt: (_d(j['bhytEmployeeRate'], 1.5), _d(j['bhytEmployerRate'], 3)),
      bhtn: (_d(j['bhtnEmployeeRate'], 1), _d(j['bhtnEmployerRate'], 1)),
      union: (_d(j['unionFeeEmployeeRate'], 1), _d(j['unionFeeEmployerRate'], 2)),
      defaultRegion: (j['defaultRegion'] as num?)?.toInt().clamp(1, 4) ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseSalary': baseSalary,
        'minSalaryRegion1': region[0],
        'minSalaryRegion2': region[1],
        'minSalaryRegion3': region[2],
        'minSalaryRegion4': region[3],
        'maxInsuranceSalary': maxSalary,
        'bhxhEmployeeRate': bhxh.$1,
        'bhxhEmployerRate': bhxh.$2,
        'bhytEmployeeRate': bhyt.$1,
        'bhytEmployerRate': bhyt.$2,
        'bhtnEmployeeRate': bhtn.$1,
        'bhtnEmployerRate': bhtn.$2,
        'unionFeeEmployeeRate': union.$1,
        'unionFeeEmployerRate': union.$2,
        'defaultRegion': defaultRegion,
      };

  String get key => toJson().toString();

  double get employeeRate => bhxh.$1 + bhyt.$1 + bhtn.$1;
  double get employerRate => bhxh.$2 + bhyt.$2 + bhtn.$2;

  /// Tiền đóng trên mức lương [salary] (đã chặn trần) — cùng cách tính với bảng lương / tính thuế.
  ({double capped, double employee, double employer, double unionEmployee, double unionEmployer}) compute(double salary) {
    final capped = salary > maxSalary ? maxSalary : salary;
    return (
      capped: capped,
      employee: capped * employeeRate / 100,
      employer: capped * employerRate / 100,
      unionEmployee: capped * union.$1 / 100,
      unionEmployer: capped * union.$2 / 100,
    );
  }

  String? validate() {
    for (final r in [bhxh, bhyt, bhtn, union]) {
      if (r.$1 < 0 || r.$1 > 50 || r.$2 < 0 || r.$2 > 50) return 'Tỷ lệ đóng phải từ 0 đến 50%';
    }
    if (baseSalary <= 0 || maxSalary <= 0) return 'Nhập lương cơ sở và mức trần';
    if (region.any((r) => r <= 0)) return 'Nhập đủ lương tối thiểu 4 vùng';
    return null;
  }
}

/// Bảo hiểm: tỷ lệ đóng BHXH / BHYT / BHTN / công đoàn, lương cơ sở, lương tối thiểu vùng, ô tính thử.
class InsuranceSettingsScreen extends StatefulWidget {
  const InsuranceSettingsScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<InsuranceSettingsScreen> createState() => _InsuranceSettingsScreenState();
}

class _InsuranceSettingsScreenState extends State<InsuranceSettingsScreen> {
  final _api = ApiService();
  InsParams _saved = InsParams();
  InsParams _p = InsParams();
  bool _loading = true;
  bool _saving = false;
  final Map<String, TextEditingController> _c = {};
  final _trySalary = TextEditingController(text: '10.000.000');
  double _tryValue = 10000000;

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('Insurance');
    } catch (_) {
      return false;
    }
  }

  TextEditingController _ctl(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _trySalary.dispose();
    super.dispose();
  }

  void _fill() {
    _ctl('base').text = settingsMoney(_p.baseSalary);
    _ctl('max').text = settingsMoney(_p.maxSalary);
    for (var i = 0; i < 4; i++) {
      _ctl('r$i').text = settingsMoney(_p.region[i]);
    }
    for (final (k, v) in [('bhxh', _p.bhxh), ('bhyt', _p.bhyt), ('bhtn', _p.bhtn), ('union', _p.union)]) {
      _ctl('${k}E').text = settingsNum(v.$1);
      _ctl('${k}C').text = settingsNum(v.$2);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _api.getInsuranceSettings();
    if (!mounted) return;
    setState(() {
      _saved = InsParams.fromJson(Map<String, dynamic>.from(data));
      _p = _saved.copy();
      _fill();
      _loading = false;
    });
  }

  Future<void> _save() async {
    final err = _p.validate();
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    setState(() => _saving = true);
    final r = await _api.saveInsuranceSettings(_p.toJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      setState(() => _saved = _p.copy());
      _toast('Đã lưu mức đóng bảo hiểm');
    } else {
      _toast(r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  @override
  Widget build(BuildContext context) {
    final edit = _canEdit;
    return SettingsPage(
      title: 'Bảo hiểm',
      subtitle: 'Tỷ lệ đóng BHXH, BHYT, BHTN, công đoàn và các mức lương làm căn cứ',
      icon: Icons.health_and_safety_outlined,
      loading: _loading,
      dirty: _p.key != _saved.key,
      saving: _saving,
      onSave: _save,
      onDiscard: () => setState(() {
        _p = _saved.copy();
        _fill();
      }),
      onResetDefaults: edit
          ? () => setState(() {
                _p = InsParams();
                _fill();
              })
          : null,
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem.', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        const SettingsNote(
            'Phiếu lương đã tạo giữ nguyên số đã tính. Bảng lương tính sau khi lưu dùng mức mới.',
            icon: Icons.info_outline_rounded),
        _ratesSection(edit),
        _salarySection(edit),
        _trySection(),
      ],
    );
  }

  Widget _ratesSection(bool edit) {
    Widget row(String label, String k, (double, double) v, void Function((double, double)) set, {String? help}) => SettingsTile(
          label: label,
          help: help,
          control: Row(mainAxisSize: MainAxisSize.min, children: [
            SettingsPercentField(
              controller: _ctl('${k}E'),
              enabled: edit,
              onChanged: (x) => setState(() => set((x ?? -1, v.$2))),
            ),
            const SizedBox(width: 8),
            SettingsPercentField(
              controller: _ctl('${k}C'),
              enabled: edit,
              onChanged: (x) => setState(() => set((v.$1, x ?? -1))),
            ),
          ]),
        );
    return SettingsSection(
      title: 'Tỷ lệ đóng',
      subtitle: 'Cột trái: người lao động · cột phải: doanh nghiệp',
      icon: Icons.percent_rounded,
      children: [
        row('BHXH', 'bhxh', _p.bhxh, (v) => _p.bhxh = v, help: 'Bảo hiểm xã hội'),
        row('BHYT', 'bhyt', _p.bhyt, (v) => _p.bhyt = v, help: 'Bảo hiểm y tế'),
        row('BHTN', 'bhtn', _p.bhtn, (v) => _p.bhtn = v, help: 'Bảo hiểm thất nghiệp'),
        row('Kinh phí công đoàn', 'union', _p.union, (v) => _p.union = v, help: 'Chỉ tính khi doanh nghiệp có tổ chức công đoàn'),
        SettingsNote(
            'Tổng bắt buộc: người lao động ${settingsNum(_p.employeeRate)}% · doanh nghiệp ${settingsNum(_p.employerRate)}% (chưa gồm công đoàn).',
            icon: Icons.summarize_outlined,
            tone: SboxTone.neutral),
      ],
    );
  }

  Widget _salarySection(bool edit) {
    final outdated = _p.region[0] < InsParams.region2026[0];
    return SettingsSection(
      title: 'Mức lương làm căn cứ',
      icon: Icons.account_balance_wallet_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Lương cơ sở',
          help: 'Dùng để tính mức trần đóng bảo hiểm',
          control: SettingsMoneyField(controller: _ctl('base'), enabled: edit, onChanged: (v) => setState(() => _p.baseSalary = v)),
        ),
        SettingsTile(
          label: 'Mức trần lương đóng bảo hiểm',
          help: 'Lương đóng vượt mức này chỉ tính bằng mức này. Thường bằng 20 × lương cơ sở = ${settingsMoney(_p.baseSalary * 20)} ₫',
          control: SettingsMoneyField(controller: _ctl('max'), enabled: edit, onChanged: (v) => setState(() => _p.maxSalary = v)),
        ),
        SettingsTile(
          label: 'Cửa hàng thuộc vùng',
          help: 'Lương đóng bảo hiểm không được thấp hơn lương tối thiểu vùng',
          control: SettingsSegment<int>(
            value: _p.defaultRegion,
            options: const [(1, 'I'), (2, 'II'), (3, 'III'), (4, 'IV')],
            onChanged: edit ? (v) => setState(() => _p.defaultRegion = v) : (_) {},
          ),
        ),
        for (var i = 0; i < 4; i++)
          SettingsTile(
            label: 'Lương tối thiểu vùng ${['I', 'II', 'III', 'IV'][i]}',
            control: SettingsMoneyField(
              controller: _ctl('r$i'),
              enabled: edit,
              onChanged: (v) => setState(() => _p.region[i] = v),
            ),
          ),
        if (outdated && edit)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.update_rounded, color: SboxColors.warningText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Lương tối thiểu vùng đang thấp hơn mức áp dụng từ 01/01/2026 '
                      '(${InsParams.region2026.map(settingsMoney).join(' / ')}). Kiểm tra lại văn bản hiện hành trước khi cập nhật.'),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.warningText),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _p.region = [...InsParams.region2026];
                  _fill();
                }),
                child: Text(tr('Dùng mức 2026')),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _trySection() {
    final r = _p.compute(_tryValue);
    final minRegion = _p.region[_p.defaultRegion - 1];
    Widget line(String k, double v, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(tr(k), style: TextStyle(color: SboxColors.slate600, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
            Text('${settingsMoney(v)} ₫', style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: color ?? SboxColors.slate900)),
          ]),
        );
    return SettingsSection(
      title: 'Tính thử',
      subtitle: 'Nhập lương đóng bảo hiểm của một nhân viên',
      icon: Icons.calculate_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Lương đóng bảo hiểm',
          control: SettingsMoneyField(controller: _trySalary, onChanged: (v) => setState(() => _tryValue = v)),
        ),
        if (_tryValue > 0 && _tryValue < minRegion)
          SettingsNote('Thấp hơn lương tối thiểu vùng ${['I', 'II', 'III', 'IV'][_p.defaultRegion - 1]} (${settingsMoney(minRegion)} ₫).',
              icon: Icons.warning_amber_rounded, tone: SboxTone.warning),
        if (_tryValue > _p.maxSalary)
          SettingsNote('Vượt mức trần — chỉ tính trên ${settingsMoney(_p.maxSalary)} ₫.', icon: Icons.info_outline_rounded, tone: SboxTone.neutral),
        line('Người lao động đóng (${settingsNum(_p.employeeRate)}%)', r.employee, strong: true, color: SboxColors.dangerText),
        line('Doanh nghiệp đóng (${settingsNum(_p.employerRate)}%)', r.employer, strong: true),
        line('Công đoàn — người lao động (${settingsNum(_p.union.$1)}%)', r.unionEmployee),
        line('Công đoàn — doanh nghiệp (${settingsNum(_p.union.$2)}%)', r.unionEmployer),
        line('Tổng chi phí doanh nghiệp', _tryValue + r.employer + r.unionEmployer),
        const SizedBox(height: 8),
      ],
    );
  }
}
