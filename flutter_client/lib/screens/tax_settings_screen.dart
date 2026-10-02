import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pit_tax_utils.dart';
import '../widgets/pos/pos_vnd_thousands_formatter.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';
import 'insurance_settings_screen.dart';

/// Thiết lập thuế TNCN: giảm trừ + biểu lũy tiến 5 bậc (ngưỡng cộng dồn theo tháng).
class TaxParams {
  TaxParams({
    this.personal = PitTaxDefaults.personalDeduction,
    this.dependent = PitTaxDefaults.dependentDeduction,
    List<double>? caps,
    List<double>? rates,
  })  : caps = caps ?? [PitTaxDefaults.bracket1Max, PitTaxDefaults.bracket2Max, PitTaxDefaults.bracket3Max, PitTaxDefaults.bracket4Max],
        rates = rates ?? [PitTaxDefaults.rate1, PitTaxDefaults.rate2, PitTaxDefaults.rate3, PitTaxDefaults.rate4, PitTaxDefaults.rate5];

  double personal;
  double dependent;

  /// Ngưỡng trên của bậc 1–4 (bậc 5 = phần trên ngưỡng 4).
  List<double> caps;

  /// Thuế suất bậc 1–5 (%).
  List<double> rates;

  TaxParams copy() => TaxParams(personal: personal, dependent: dependent, caps: [...caps], rates: [...rates]);

  static double _d(dynamic v, double f) => v is num ? v.toDouble() : double.tryParse('$v') ?? f;

  factory TaxParams.fromJson(Map<String, dynamic> j) {
    final d = TaxParams();
    return TaxParams(
      personal: _d(j['personalDeduction'], d.personal),
      dependent: _d(j['dependentDeduction'], d.dependent),
      caps: [for (var i = 0; i < 4; i++) _d(j['taxBracket${i + 1}Max'], d.caps[i])],
      rates: [
        for (var i = 0; i < 4; i++) _d(j['taxRate${i + 1}'], d.rates[i]),
        // Bậc 5: ưu tiên taxRate5, dữ liệu 7 bậc cũ lấy taxRate7.
        _d(j['taxRate5'] ?? j['taxRate7'], d.rates[4]),
      ],
    );
  }

  /// Lưu dạng 5 bậc: ngưỡng 5, 6 trùng ngưỡng 4; thuế suất 6, 7 trùng bậc 5 (đúng định dạng màn cũ).
  Map<String, dynamic> toJson() => {
        'personalDeduction': personal,
        'dependentDeduction': dependent,
        for (var i = 0; i < 4; i++) 'taxBracket${i + 1}Max': caps[i],
        for (var i = 0; i < 4; i++) 'taxRate${i + 1}': rates[i],
        'taxBracket5Max': caps[3],
        'taxRate5': rates[4],
        'taxBracket6Max': caps[3],
        'taxRate6': rates[4],
        'taxRate7': rates[4],
      };

  String get key => toJson().toString();

  String? validate() {
    for (var i = 1; i < 4; i++) {
      if (caps[i] <= caps[i - 1]) return 'Ngưỡng bậc ${i + 1} phải lớn hơn bậc $i';
    }
    if (caps[0] <= 0) return 'Ngưỡng bậc 1 phải lớn hơn 0';
    if (rates.any((r) => r < 0 || r > 100)) return 'Thuế suất phải từ 0 đến 100%';
    if (personal < 0 || dependent < 0) return 'Mức giảm trừ không được âm';
    return null;
  }

  /// Tính thử cho 1 tháng — cùng công thức với bảng lương / server.
  ({double insurance, double deduction, double taxable, double tax, double net}) compute({
    required double gross,
    required double insuranceSalary,
    required int dependents,
    required InsParams ins,
  }) {
    final insurance = ins.compute(insuranceSalary).employee;
    final deduction = personal + dependent * dependents;
    final taxable = (gross - insurance - deduction).clamp(0, double.infinity).toDouble();
    final tax = calculateProgressivePit(taxable, toJson());
    return (insurance: insurance, deduction: deduction, taxable: taxable, tax: tax, net: gross - insurance - tax);
  }
}

class TaxSettingsScreen extends StatefulWidget {
  const TaxSettingsScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends State<TaxSettingsScreen> {
  final _api = ApiService();
  TaxParams _saved = TaxParams();
  TaxParams _p = TaxParams();
  InsParams _ins = InsParams();
  List<Map<String, dynamic>> _deps = [];
  bool _loading = true;
  bool _saving = false;
  final Map<String, TextEditingController> _c = {};
  double _gross = 25000000;
  double _insSalary = 10000000;
  int _dependents = 1;
  String _depQuery = '';

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('Tax');
    } catch (_) {
      return false;
    }
  }

  TextEditingController _ctl(String k, [String text = '']) => _c.putIfAbsent(k, () => TextEditingController(text: text));

  @override
  void initState() {
    super.initState();
    _ctl('gross', settingsMoney(_gross));
    _ctl('insSalary', settingsMoney(_insSalary));
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    _ctl('personal').text = settingsMoney(_p.personal);
    _ctl('dependent').text = settingsMoney(_p.dependent);
    for (var i = 0; i < 4; i++) {
      _ctl('cap$i').text = settingsMoney(_p.caps[i]);
    }
    for (var i = 0; i < 5; i++) {
      _ctl('rate$i').text = settingsNum(_p.rates[i]);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await Future.wait([_api.getTaxSettings(), _api.getInsuranceSettings()]);
    List<dynamic> deps = const [];
    try {
      deps = await _api.getEmployeeTaxDeductions();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saved = TaxParams.fromJson(Map<String, dynamic>.from(res[0]));
      _ins = InsParams.fromJson(Map<String, dynamic>.from(res[1]));
      _p = _saved.copy();
      _deps = [for (final d in deps.whereType<Map>()) Map<String, dynamic>.from(d)];
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
    final r = await _api.saveTaxSettings(_p.toJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      setState(() => _saved = _p.copy());
      _toast('Đã lưu thiết lập thuế TNCN');
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
      title: 'Thuế thu nhập cá nhân',
      subtitle: 'Giảm trừ gia cảnh, biểu thuế lũy tiến theo tháng, người phụ thuộc của nhân viên',
      icon: Icons.receipt_long_outlined,
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
                _p = TaxParams();
                _fill();
              })
          : null,
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem.', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        _deductionSection(edit),
        _bracketSection(edit),
        _trySection(),
        _dependentsSection(edit),
      ],
    );
  }

  Widget _deductionSection(bool edit) => SettingsSection(
        title: 'Giảm trừ gia cảnh (mỗi tháng)',
        icon: Icons.family_restroom_rounded,
        children: [
          SettingsTile(
            divider: false,
            label: 'Bản thân người nộp thuế',
            control: SettingsMoneyField(controller: _ctl('personal'), enabled: edit, onChanged: (v) => setState(() => _p.personal = v)),
          ),
          SettingsTile(
            label: 'Mỗi người phụ thuộc',
            control: SettingsMoneyField(controller: _ctl('dependent'), enabled: edit, onChanged: (v) => setState(() => _p.dependent = v)),
          ),
        ],
      );

  Widget _bracketSection(bool edit) {
    String label(int i) => i == 0
        ? 'Bậc 1: đến ${settingsMoney(_p.caps[0])}'
        : i < 4
            ? 'Bậc ${i + 1}: trên ${settingsMoney(_p.caps[i - 1])} đến ${settingsMoney(_p.caps[i])}'
            : 'Bậc 5: trên ${settingsMoney(_p.caps[3])}';
    return SettingsSection(
      title: 'Biểu thuế lũy tiến',
      subtitle: 'Thu nhập tính thuế mỗi tháng, tính cộng dồn từng phần theo bậc',
      icon: Icons.stacked_bar_chart_rounded,
      children: [
        for (var i = 0; i < 5; i++)
          SettingsTile(
            divider: i > 0,
            label: label(i),
            control: Row(mainAxisSize: MainAxisSize.min, children: [
              if (i < 4) ...[
                SettingsMoneyField(
                  controller: _ctl('cap$i'),
                  enabled: edit,
                  width: 160,
                  onChanged: (v) => setState(() => _p.caps[i] = v),
                ),
                const SizedBox(width: 8),
              ],
              SettingsPercentField(
                controller: _ctl('rate$i'),
                enabled: edit,
                width: 90,
                onChanged: (v) => setState(() => _p.rates[i] = v ?? -1),
              ),
            ]),
          ),
        if (_p.validate() != null) SettingsNote(_p.validate()!, icon: Icons.error_outline_rounded, tone: SboxTone.danger),
      ],
    );
  }

  Widget _trySection() {
    final r = _p.validate() == null ? _p.compute(gross: _gross, insuranceSalary: _insSalary, dependents: _dependents, ins: _ins) : null;
    Widget line(String k, double? v, {bool strong = false, Color? color, String sign = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(tr(k), style: TextStyle(color: SboxColors.slate600, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
            Text(v == null ? '—' : '$sign${settingsMoney(v)} ₫',
                style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: color ?? SboxColors.slate900)),
          ]),
        );
    return SettingsSection(
      title: 'Tính thử thuế một tháng',
      subtitle: 'Dùng mức đóng bảo hiểm hiện hành của cửa hàng',
      icon: Icons.calculate_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Tổng thu nhập chịu thuế',
          help: 'Lương, thưởng, phụ cấp chịu thuế',
          control: SettingsMoneyField(controller: _ctl('gross'), onChanged: (v) => setState(() => _gross = v)),
        ),
        SettingsTile(
          label: 'Lương đóng bảo hiểm',
          control: SettingsMoneyField(controller: _ctl('insSalary'), onChanged: (v) => setState(() => _insSalary = v)),
        ),
        SettingsTile(
          label: 'Số người phụ thuộc',
          control: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: _dependents > 0 ? () => setState(() => _dependents--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_dependents', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            IconButton(onPressed: () => setState(() => _dependents++), icon: const Icon(Icons.add_circle_outline)),
          ]),
        ),
        const Divider(height: 16),
        line('Bảo hiểm người lao động đóng', r?.insurance, sign: '−'),
        line('Giảm trừ gia cảnh', r?.deduction, sign: '−'),
        line('Thu nhập tính thuế', r?.taxable),
        line('Thuế TNCN phải nộp', r?.tax, strong: true, color: SboxColors.dangerText),
        line('Thực nhận', r?.net, strong: true, color: SboxColors.successText),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─── Người phụ thuộc theo nhân viên ───────────────────────────

  Widget _dependentsSection(bool edit) {
    final q = _depQuery.trim().toLowerCase();
    final list = _deps
        .where((d) => q.isEmpty || '${d['employeeName']} ${d['employeeCode']}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => ((b['numberOfDependents'] as num?) ?? 0).compareTo((a['numberOfDependents'] as num?) ?? 0));
    final withDeps = _deps.where((d) => ((d['numberOfDependents'] as num?) ?? 0) > 0).length;
    return SettingsSection(
      title: 'Người phụ thuộc của nhân viên',
      subtitle: '$withDeps/${_deps.length} nhân viên có đăng ký người phụ thuộc',
      icon: Icons.people_alt_outlined,
      children: [
        TextField(
          onChanged: (v) => setState(() => _depQuery = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: tr('Tìm nhân viên'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 4),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có nhân viên.', style: TextStyle(color: SboxColors.slate500))),
        for (final d in list.take(60))
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: edit ? () => _editDependents(d) : null,
            title: Text(tr('${d['employeeName'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('${d['employeeCode'] ?? ''}'
                '${_docs(d).isNotEmpty || '${d['dependentRegistrationFormUrl'] ?? ''}'.isNotEmpty ? ' · có hồ sơ đính kèm' : ''}')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              SboxStatusChip(
                label: '${(d['numberOfDependents'] as num?) ?? 0} người phụ thuộc',
                tone: ((d['numberOfDependents'] as num?) ?? 0) > 0 ? SboxTone.brand : SboxTone.neutral,
              ),
              if (edit) const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
          ),
        if (list.length > 60)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(tr('Đang hiện 60/${list.length} — gõ tên để tìm'), style: const TextStyle(color: SboxColors.slate500)),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _docs(Map<String, dynamic> d) {
    try {
      final raw = d['dependentDocumentsJson'];
      final v = raw is String ? jsonDecode(raw) : raw;
      return [if (v is List) for (final x in v.whereType<Map>()) Map<String, dynamic>.from(x)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _editDependents(Map<String, dynamic> d) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DependentsDialog(employee: d, docs: _docs(d), tax: _p),
    );
    if (saved == null) return;
    final r = await _api.saveEmployeeTaxDeduction(saved);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      setState(() => d.addAll(saved));
      _toast('Đã lưu người phụ thuộc của ${d['employeeName'] ?? ''}');
    } else {
      _toast(r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }
}

/// Sửa người phụ thuộc + giấy tờ của một nhân viên.
class _DependentsDialog extends StatefulWidget {
  const _DependentsDialog({required this.employee, required this.docs, required this.tax});

  final Map<String, dynamic> employee;
  final List<Map<String, dynamic>> docs;
  final TaxParams tax;

  @override
  State<_DependentsDialog> createState() => _DependentsDialogState();
}

class _DependentsDialogState extends State<_DependentsDialog> {
  final _api = ApiService();
  late int _count = ((widget.employee['numberOfDependents'] as num?) ?? 0).toInt();
  late final _other = TextEditingController(
      text: settingsMoney(((widget.employee['otherExemptions'] as num?) ?? 0).toDouble()));
  late String _form = '${widget.employee['dependentRegistrationFormUrl'] ?? ''}';
  late List<Map<String, dynamic>> _docs = [...widget.docs];
  bool _uploading = false;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Future<void> _upload({required bool form}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final f = picked?.files.firstOrNull;
    if (f?.bytes == null) return;
    setState(() => _uploading = true);
    final up = await _api.uploadFile(f!.bytes!, f.name, folder: 'tax/dependents');
    if (!mounted) return;
    setState(() => _uploading = false);
    final data = up['data'];
    final path = data is Map ? (data['filePath'] ?? data['fileUrl'] ?? data['url'])?.toString() : null;
    if (up['isSuccess'] != true || path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('${up['message'] ?? 'Tải tệp thất bại'}'))));
      return;
    }
    setState(() {
      if (form) {
        _form = path;
      } else {
        _docs = [..._docs, {'fileName': f.name, 'url': path, 'note': '', 'uploadedAt': DateTime.now().toIso8601String()}];
      }
    });
  }

  void _open(String path) {
    final uri = Uri.tryParse(_api.getFileUrl(path));
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final other = PosVndThousandsFormatter.parse(_other.text);
    final total = widget.tax.personal + widget.tax.dependent * _count + other;
    return AlertDialog(
      title: Text(tr('${e['employeeName'] ?? ''} · ${e['employeeCode'] ?? ''}')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(tr('Số người phụ thuộc'), style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(onPressed: _count > 0 ? () => setState(() => _count--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_count', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              IconButton(onPressed: () => setState(() => _count++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _other,
              keyboardType: TextInputType.number,
              inputFormatters: [PosVndThousandsFormatter(), FilteringTextInputFormatter.deny(RegExp(r'-'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Khoản miễn thuế khác / tháng'),
                suffixText: '₫',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SettingsNote('Tổng giảm trừ mỗi tháng: ${settingsMoney(total)} ₫ (bản thân + ${settingsMoney(widget.tax.dependent * _count)} người phụ thuộc + khác)',
                icon: Icons.summarize_outlined, tone: SboxTone.brand),
            Text(tr('Phiếu đăng ký người phụ thuộc'), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (_form.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(tr('Đã có phiếu đăng ký')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: tr('Xem'), onPressed: () => _open(_form), icon: const Icon(Icons.open_in_new, size: 18)),
                  IconButton(tooltip: tr('Bỏ'), onPressed: () => setState(() => _form = ''), icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _uploading ? null : () => _upload(form: true),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(tr(_form.isEmpty ? 'Tải phiếu đăng ký (PDF / ảnh)' : 'Đổi phiếu đăng ký')),
              ),
            ),
            const SizedBox(height: 4),
            Text(tr('Giấy tờ người phụ thuộc'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (var i = 0; i < _docs.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file, size: 18),
                title: Text('${_docs[i]['fileName'] ?? 'Tài liệu'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: () => _open('${_docs[i]['url'] ?? ''}'), icon: const Icon(Icons.open_in_new, size: 18)),
                  IconButton(onPressed: () => setState(() => _docs = [..._docs]..removeAt(i)), icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _uploading ? null : () => _upload(form: false),
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: Text(tr('Thêm giấy tờ')),
              ),
            ),
            if (_uploading) const LinearProgressIndicator(minHeight: 2),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _uploading
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                    'employeeId': e['employeeId'],
                    'numberOfDependents': _count,
                    'mandatoryInsurance': ((e['mandatoryInsurance'] as num?) ?? 0).toDouble(),
                    'otherExemptions': other,
                    'dependentRegistrationFormUrl': _form,
                    'dependentDocumentsJson': jsonEncode(_docs),
                  }),
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
