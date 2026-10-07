import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Một bậc phạt: từ [threshold] (phút hoặc lần) trở lên → [amount].
class PenaltyTier {
  PenaltyTier(this.threshold, this.amount);
  int threshold;
  double amount;
}

/// Mức phạt chấm công của cửa hàng — khớp cách server tạo phiếu phạt tự động.
class PenaltyParams {
  PenaltyParams({
    List<PenaltyTier>? late,
    List<PenaltyTier>? early,
    List<PenaltyTier>? repeat,
    this.forgot = 100000,
    this.absent = 500000,
    this.violation = 200000,
    this.method = 'Salary',
    this.autoApproveHours = 2,
  })  : late = late ?? [PenaltyTier(15, 50000), PenaltyTier(30, 100000), PenaltyTier(60, 200000)],
        early = early ?? [PenaltyTier(15, 50000), PenaltyTier(30, 100000), PenaltyTier(60, 200000)],
        repeat = repeat ?? [PenaltyTier(3, 100000), PenaltyTier(5, 200000), PenaltyTier(10, 500000)];

  List<PenaltyTier> late;
  List<PenaltyTier> early;
  List<PenaltyTier> repeat;
  double forgot;
  double absent;

  /// Không dùng khi tạo phiếu tự động — giữ nguyên giá trị đã lưu.
  double violation;
  String method;
  int autoApproveHours;

  PenaltyParams copy() => PenaltyParams.fromJson(toJson());

  static int _i(dynamic v, int f) => v is num ? v.toInt() : int.tryParse('$v') ?? f;
  static double _d(dynamic v, double f) => v is num ? v.toDouble() : double.tryParse('$v') ?? f;

  factory PenaltyParams.fromJson(Map<String, dynamic> j) {
    final d = PenaltyParams();
    List<PenaltyTier> tiers(String t, String a, List<PenaltyTier> def) =>
        [for (var i = 0; i < 3; i++) PenaltyTier(_i(j['$t${i + 1}'], def[i].threshold), _d(j['$a${i + 1}'], def[i].amount))];
    return PenaltyParams(
      late: tiers('lateMinutes', 'latePenalty', d.late),
      early: tiers('earlyMinutes', 'earlyPenalty', d.early),
      repeat: tiers('repeatCount', 'repeatPenalty', d.repeat),
      forgot: _d(j['forgotCheckPenalty'], d.forgot),
      absent: _d(j['unauthorizedLeavePenalty'], d.absent),
      violation: _d(j['violationPenalty'], d.violation),
      method: j['collectionMethod']?.toString() == 'Cash' ? 'Cash' : 'Salary',
      autoApproveHours: _i(j['autoApproveHoursAfterShift'], 2),
    );
  }

  Map<String, dynamic> toJson() => {
        for (var i = 0; i < 3; i++) ...{
          'lateMinutes${i + 1}': late[i].threshold,
          'latePenalty${i + 1}': late[i].amount,
          'earlyMinutes${i + 1}': early[i].threshold,
          'earlyPenalty${i + 1}': early[i].amount,
          'repeatCount${i + 1}': repeat[i].threshold,
          'repeatPenalty${i + 1}': repeat[i].amount,
        },
        'forgotCheckPenalty': forgot,
        'unauthorizedLeavePenalty': absent,
        'violationPenalty': violation,
        'collectionMethod': method,
        'autoApproveHoursAfterShift': autoApproveHours,
      };

  String get key => toJson().toString();

  /// Bậc cao nhất đạt được (giống server: xét từ bậc 3 xuống).
  static (int, double) tierOf(List<PenaltyTier> tiers, int value) {
    for (var i = 2; i >= 0; i--) {
      if (value >= tiers[i].threshold) return (i + 1, tiers[i].amount);
    }
    return (0, 0);
  }

  /// Phiếu phạt đi trễ [minutes] phút, là lần vi phạm thứ [nth] trong tháng (gộp trễ + về sớm).
  ({int tier, double base, double surcharge}) lateTicket(int minutes, int nth) {
    final (tier, base) = tierOf(late, minutes);
    if (tier == 0) return (tier: 0, base: 0, surcharge: 0);
    return (tier: tier, base: base, surcharge: tierOf(repeat, nth).$2);
  }

  String? validate() {
    for (final (name, t) in [('Đi trễ', late), ('Về sớm', early), ('Tái phạm', repeat)]) {
      if (t[0].threshold <= 0) return '$name: mốc bậc 1 phải lớn hơn 0';
      if (!(t[0].threshold < t[1].threshold && t[1].threshold < t[2].threshold)) return '$name: mốc các bậc phải tăng dần';
      if (t.any((x) => x.amount < 0)) return '$name: số tiền không được âm';
    }
    return null;
  }
}

/// Mức phạt: đi trễ, về sớm theo bậc phút; tái phạm trong tháng; quên chấm, nghỉ không phép; cách thu.
class PenaltySettingsScreen extends StatefulWidget {
  const PenaltySettingsScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<PenaltySettingsScreen> createState() => _PenaltySettingsScreenState();
}

class _PenaltySettingsScreenState extends State<PenaltySettingsScreen> {
  final _api = ApiService();
  PenaltyParams _saved = PenaltyParams();
  PenaltyParams _p = PenaltyParams();
  bool _loading = true;
  bool _saving = false;
  final Map<String, TextEditingController> _c = {};
  int _tryMinutes = 20;
  int _tryNth = 4;

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('PenaltySetup');
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
    super.dispose();
  }

  void _fill() {
    for (final (k, t) in [('late', _p.late), ('early', _p.early), ('repeat', _p.repeat)]) {
      for (var i = 0; i < 3; i++) {
        _ctl('$k${i}t').text = '${t[i].threshold}';
        _ctl('$k${i}a').text = settingsMoney(t[i].amount);
      }
    }
    _ctl('forgot').text = settingsMoney(_p.forgot);
    _ctl('absent').text = settingsMoney(_p.absent);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getPenaltySettings();
    if (!mounted) return;
    setState(() {
      _saved = r['isSuccess'] == true && r['data'] is Map ? PenaltyParams.fromJson(Map<String, dynamic>.from(r['data'] as Map)) : PenaltyParams();
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
    final r = await _api.savePenaltySettings(_p.toJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      setState(() => _saved = _p.copy());
      _toast('Đã lưu mức phạt');
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
    final err = _p.validate();
    return SettingsPage(
      title: 'Mức phạt',
      subtitle: 'Phiếu phạt được tạo tự động khi đồng bộ chấm công, quản lý duyệt trước khi trừ',
      icon: Icons.gavel_outlined,
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
                _p = PenaltyParams()..violation = _p.violation;
                _fill();
              })
          : null,
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem.', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        if (err != null) SettingsNote(err, icon: Icons.error_outline_rounded, tone: SboxTone.danger),
        _tierSection('Đi trễ', 'Tính từ sau giờ vào ca (đã trừ phút miễn trễ của ca)', Icons.directions_run_rounded, 'late', _p.late, 'phút', edit),
        _tierSection('Về sớm', 'Tính trước giờ ra ca (đã trừ phút miễn về sớm của ca)', Icons.logout_rounded, 'early', _p.early, 'phút', edit),
        _tierSection('Tái phạm trong tháng', 'Cộng thêm vào phiếu trễ / về sớm từ lần vi phạm thứ N trong tháng (gộp cả trễ và về sớm)',
            Icons.repeat_rounded, 'repeat', _p.repeat, 'lần', edit),
        _otherSection(edit),
        _trySection(),
      ],
    );
  }

  Widget _tierSection(String title, String sub, IconData icon, String k, List<PenaltyTier> t, String unit, bool edit) {
    return SettingsSection(
      title: title,
      subtitle: sub,
      icon: icon,
      children: [
        for (var i = 0; i < 3; i++)
          SettingsTile(
            divider: i > 0,
            label: 'Bậc ${i + 1}',
            help: i < 2
                ? 'Từ ${t[i].threshold} đến dưới ${t[i + 1].threshold} $unit'
                : 'Từ ${t[i].threshold} $unit trở lên',
            control: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _ctl('$k${i}t'),
                  enabled: edit,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: InputDecoration(isDense: true, suffixText: unit, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  onChanged: (v) => setState(() => t[i].threshold = int.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 8),
              SettingsMoneyField(controller: _ctl('$k${i}a'), enabled: edit, width: 150, onChanged: (v) => setState(() => t[i].amount = v)),
            ]),
          ),
      ],
    );
  }

  Widget _otherSection(bool edit) => SettingsSection(
        title: 'Vi phạm khác & cách thu',
        icon: Icons.rule_rounded,
        children: [
          SettingsTile(
            divider: false,
            label: 'Quên chấm công',
            help: 'Thiếu lần chấm vào hoặc ra trong ngày có lịch (0 = không phạt)',
            control: SettingsMoneyField(controller: _ctl('forgot'), enabled: edit, onChanged: (v) => setState(() => _p.forgot = v)),
          ),
          SettingsTile(
            label: 'Nghỉ không phép',
            help: 'Có lịch làm nhưng không chấm công, không có đơn nghỉ (0 = không phạt)',
            control: SettingsMoneyField(controller: _ctl('absent'), enabled: edit, onChanged: (v) => setState(() => _p.absent = v)),
          ),
          SettingsTile(
            label: 'Cách thu tiền phạt',
            help: _p.method == 'Cash' ? 'Nhân viên nộp tiền mặt, ghi vào sổ thu chi' : 'Trừ vào lương kỳ này sau khi phiếu được duyệt',
            control: SettingsSegment<String>(
              value: _p.method,
              options: const [('Salary', 'Trừ lương'), ('Cash', 'Tiền mặt')],
              onChanged: edit ? (v) => setState(() => _p.method = v) : (_) {},
            ),
          ),
          SettingsTile(
            label: 'Tự duyệt phạt sau kết ca',
            help: _p.autoApproveHours <= 0
                ? 'Tắt — chờ quản lý duyệt thủ công'
                : 'Sau kết ca ${_p.autoApproveHours} giờ, nếu NV chưa khiếu nại → tự duyệt phạt',
            control: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: edit && _p.autoApproveHours > 0 ? () => setState(() => _p.autoApproveHours--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  _p.autoApproveHours <= 0 ? 'Tắt' : '${_p.autoApproveHours}h',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: edit && _p.autoApproveHours < 72 ? () => setState(() => _p.autoApproveHours++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
          ),
        ],
      );

  Widget _trySection() {
    final r = _p.validate() == null ? _p.lateTicket(_tryMinutes, _tryNth) : null;
    Widget stepper(String label, int value, ValueChanged<int> set, {int step = 1, int min = 0}) => SettingsTile(
          label: label,
          control: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: value - step >= min ? () => set(value - step) : null, icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(onPressed: () => set(value + step), icon: const Icon(Icons.add_circle_outline)),
          ]),
        );
    return SettingsSection(
      title: 'Tính thử',
      subtitle: 'Một lần đi trễ sẽ bị phạt bao nhiêu',
      icon: Icons.calculate_outlined,
      children: [
        stepper('Số phút đi trễ', _tryMinutes, (v) => setState(() => _tryMinutes = v), step: 5),
        stepper('Là lần vi phạm thứ mấy trong tháng', _tryNth, (v) => setState(() => _tryNth = v), min: 1),
        if (r != null)
          SettingsNote(
            r.tier == 0
                ? 'Chưa tới mốc bậc 1 (${_p.late[0].threshold} phút) — không tạo phiếu phạt.'
                : 'Phiếu phạt bậc ${r.tier}: ${settingsMoney(r.base)} ₫'
                    '${r.surcharge > 0 ? ' + tái phạm ${settingsMoney(r.surcharge)} ₫' : ''} = ${settingsMoney(r.base + r.surcharge)} ₫',
            icon: Icons.receipt_long_rounded,
            tone: r.tier == 0 ? SboxTone.neutral : SboxTone.warning,
          ),
      ],
    );
  }
}
