import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/shift_records_calculator.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Giá trị tham số hệ thống (AppSettings của cửa hàng).
class SystemParams {
  SystemParams({
    this.dayEnd = Duration.zero,
    this.decimal = false,
    this.minPercent = 80,
    this.minHalfHours = 1,
    this.allowCorrection = true,
    this.correctionLevels = 1,
    this.leaveLevels = 1,
  });

  /// Ranh giới ngày làm việc: chấm trước giờ này tính cho ngày hôm trước.
  Duration dayEnd;
  bool decimal;
  double minPercent;
  double minHalfHours;
  bool allowCorrection;
  int correctionLevels;
  int leaveLevels;

  SystemParams copy() => SystemParams(
        dayEnd: dayEnd,
        decimal: decimal,
        minPercent: minPercent,
        minHalfHours: minHalfHours,
        allowCorrection: allowCorrection,
        correctionLevels: correctionLevels,
        leaveLevels: leaveLevels,
      );

  String get dayEndText =>
      '${dayEnd.inHours.toString().padLeft(2, '0')}:${(dayEnd.inMinutes % 60).toString().padLeft(2, '0')}';

  /// Lưu ý: «Quy tắc làm tròn» và «Ngày chốt công» không có trong danh sách — chưa được dùng khi tính công / lương.
  Map<String, String> toSettings() => {
        'day_end_time': '$dayEndText:00',
        'decimal_work_day_enabled': '$decimal',
        'min_work_day_percent': '$minPercent',
        'min_half_day_hours': '$minHalfHours',
        'allow_manual_correction': '$allowCorrection',
        'attendance_approval_levels': '$correctionLevels',
        'leave_approval_levels': '$leaveLevels',
      };

  static const descriptions = {
    'day_end_time': 'Giờ kết thúc ngày làm việc',
    'decimal_work_day_enabled': 'Tính công theo thập phân (0.1–1.0, tắt ngưỡng %)',
    'min_work_day_percent': '% giờ chuẩn trong ngày để đủ 1 công (mặc định 80)',
    'min_half_day_hours': 'Giờ tối thiểu để tính nửa công (mặc định 1)',
    'allow_manual_correction': 'Cho phép chấm công bù',
    'attendance_approval_levels': 'Số cấp phê duyệt yêu cầu chấm công',
    'leave_approval_levels': 'Số cấp phê duyệt đơn nghỉ phép',
  };

  static SystemParams fromSettings(Map<String, String?> v) {
    Duration end = Duration.zero;
    final p = (v['day_end_time'] ?? '').split(':');
    if (p.length >= 2) end = Duration(hours: int.tryParse(p[0]) ?? 0, minutes: int.tryParse(p[1]) ?? 0);
    return SystemParams(
      dayEnd: end,
      decimal: parseDecimalWorkDayEnabled(appSettingValue: v['decimal_work_day_enabled']),
      minPercent: parseMinWorkDayPercent(
        percentAppSettingValue: v['min_work_day_percent'],
        legacyHoursAppSettingValue: v['min_hours_for_work_day'],
      ),
      minHalfHours: parseMinHalfDayHours(appSettingValue: v['min_half_day_hours']),
      allowCorrection: v['allow_manual_correction'] != 'false',
      correctionLevels: (int.tryParse(v['attendance_approval_levels'] ?? '') ?? 1).clamp(1, 3),
      leaveLevels: (int.tryParse(v['leave_approval_levels'] ?? '') ?? 1).clamp(1, 3),
    );
  }

  String? validate() {
    if (minPercent < 1 || minPercent > 100) return '% đủ 1 công phải từ 1 đến 100';
    if (minHalfHours < 0 || minHalfHours > 24) return 'Giờ tối thiểu nửa công phải từ 0 đến 24';
    return null;
  }

  @override
  bool operator ==(Object other) => other is SystemParams && other.toSettings().toString() == toSettings().toString();

  @override
  int get hashCode => toSettings().toString().hashCode;
}

/// Tham số hệ thống: ranh giới ngày làm việc, cách tính công, chấm công bù, số cấp duyệt.
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key, this.canEditOverride});

  /// Bỏ qua kiểm quyền sửa (test).
  final bool? canEditOverride;

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  static const _keys = [
    'day_end_time',
    'decimal_work_day_enabled',
    'min_work_day_percent',
    'min_hours_for_work_day',
    'min_half_day_hours',
    'allow_manual_correction',
    'attendance_approval_levels',
    'leave_approval_levels',
  ];

  final _api = ApiService();
  SystemParams _saved = SystemParams();
  SystemParams _p = SystemParams();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final TextEditingController _percent = TextEditingController();
  late final TextEditingController _half = TextEditingController();

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('SystemSettings');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _percent.dispose();
    _half.dispose();
    super.dispose();
  }

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _fillControllers() {
    _percent.text = _num(_p.minPercent);
    _half.text = _num(_p.minHalfHours);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await Future.wait(_keys.map(_api.getAppSetting));
    if (!mounted) return;
    final values = <String, String?>{};
    for (var i = 0; i < _keys.length; i++) {
      final r = res[i];
      if (r['isSuccess'] == true && r['data'] is Map) values[_keys[i]] = (r['data'] as Map)['value']?.toString();
    }
    // Lỗi kết nối (có errorKind) ở mọi khóa → báo lỗi; khóa chưa có = dùng mặc định (cửa hàng mới).
    final offline = res.every((r) => r['isSuccess'] != true && r['errorKind'] != null);
    setState(() {
      _loading = false;
      if (offline) _error = res.first['message']?.toString();
      _saved = SystemParams.fromSettings(values);
      _p = _saved.copy();
      _fillControllers();
    });
  }

  void _set(VoidCallback f) => setState(f);

  Future<void> _save() async {
    final err = _p.validate();
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    setState(() => _saving = true);
    final changed = _p.toSettings().entries.where((e) => _saved.toSettings()[e.key] != e.value).toList();
    final results = await Future.wait(changed.map((e) => _api.upsertAppSetting(
          key: e.key,
          value: e.value,
          description: SystemParams.descriptions[e.key],
        )));
    if (!mounted) return;
    setState(() => _saving = false);
    final failed = results.where((r) => r['isSuccess'] != true).toList();
    if (failed.isEmpty) {
      setState(() => _saved = _p.copy());
      _toast('Đã lưu tham số hệ thống');
    } else {
      _toast('Không lưu được: ${failed.first['message'] ?? 'lỗi không xác định'}', error: true);
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
      title: 'Tham số hệ thống',
      subtitle: 'Ranh giới ngày làm việc, cách tính công, chấm công bù và quy trình duyệt',
      icon: Icons.settings_suggest_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      dirty: _p != _saved,
      saving: _saving,
      onSave: _save,
      onDiscard: () => _set(() {
        _p = _saved.copy();
        _fillControllers();
      }),
      onResetDefaults: edit
          ? () => _set(() {
                _p = SystemParams();
                _fillControllers();
              })
          : null,
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem. Liên hệ quản trị để thay đổi.', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        _dayEndSection(edit),
        _creditSection(edit),
        _approvalSection(edit),
      ],
    );
  }

  // ─── Ngày làm việc ─────────────────────────────────────────────

  Widget _dayEndSection(bool edit) {
    final end = _p.dayEndText;
    final night = _p.dayEnd > Duration.zero;
    return SettingsSection(
      title: 'Ngày làm việc kết thúc lúc',
      subtitle: 'Dùng cho cửa hàng có ca đêm: lần chấm trước giờ này được tính cho ngày hôm trước',
      icon: Icons.nightlight_round,
      children: [
        SettingsTile(
          divider: false,
          label: 'Giờ kết thúc ngày',
          help: night ? 'Chấm công từ 00:00 đến trước $end tính cho ngày hôm trước' : 'Mặc định 00:00 — ngày tính theo lịch',
          control: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final h in const [0, 4, 6])
              ChoiceChip(
                label: Text('${h.toString().padLeft(2, '0')}:00'),
                selected: _p.dayEnd == Duration(hours: h),
                showCheckmark: false,
                onSelected: edit ? (_) => _set(() => _p.dayEnd = Duration(hours: h)) : null,
              ),
            OutlinedButton.icon(
              onPressed: edit
                  ? () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: _p.dayEnd.inHours, minute: _p.dayEnd.inMinutes % 60),
                        builder: (ctx, child) =>
                            MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
                      );
                      if (t != null) _set(() => _p.dayEnd = Duration(hours: t.hour, minutes: t.minute));
                    }
                  : null,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(end),
            ),
          ]),
        ),
        SettingsNote(night
            ? 'Ví dụ: ca từ 22:00 ngày 01 đến 06:00 ngày 02. Lần chấm ra lúc 05:50 (trước $end) vẫn tính cho ngày 01, đủ 1 cặp vào–ra.'
            : 'Ví dụ: ca từ 22:00 đến 06:00 hôm sau. Với 00:00, lần chấm ra lúc 05:50 bị tính sang ngày hôm sau. Nếu có ca đêm, đặt khoảng 04:00–06:00.'),
      ],
    );
  }

  // ─── Cách tính công ────────────────────────────────────────────

  Widget _creditSection(bool edit) {
    InputDecoration dec(String suffix) => InputDecoration(
          isDense: true,
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );
    final fmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return SettingsSection(
      title: 'Cách tính công trong ngày',
      subtitle: 'Từ số giờ làm thực tế so với giờ chuẩn 1 công của nhân viên (mặc định 8 giờ)',
      icon: Icons.calculate_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Kiểu tính công',
          control: SettingsSegment<bool>(
            value: _p.decimal,
            options: const [(false, 'Theo ngưỡng (1 / 0,5)'), (true, 'Thập phân (0,1 – 1)')],
            onChanged: edit ? (v) => _set(() => _p.decimal = v) : (_) {},
          ),
        ),
        if (!_p.decimal)
          SettingsTile(
            label: 'Đủ 1 công khi làm từ',
            help: 'Phần trăm giờ chuẩn. Dưới mức này nhưng trên mức nửa công thì được 0,5 công',
            control: SizedBox(
              width: 120,
              child: TextField(
                controller: _percent,
                enabled: edit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: fmt,
                decoration: dec('%'),
                onChanged: (v) => _set(() => _p.minPercent = double.tryParse(v.replaceAll(',', '.')) ?? -1),
              ),
            ),
          ),
        SettingsTile(
          label: 'Không tính công nếu làm dưới',
          help: _p.decimal ? 'Dưới mức này = 0 công, trên mức này làm tròn bậc 0,1' : 'Dưới mức này = 0 công',
          control: SizedBox(
            width: 120,
            child: TextField(
              controller: _half,
              enabled: edit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: fmt,
              decoration: dec('giờ'),
              onChanged: (v) => _set(() => _p.minHalfHours = double.tryParse(v.replaceAll(',', '.')) ?? -1),
            ),
          ),
        ),
        _creditPreview(),
      ],
    );
  }

  /// Bảng minh họa: số giờ làm → số công (giờ chuẩn 8h), cùng công thức với bảng công.
  Widget _creditPreview() {
    const hours = [0.5, 2.0, 4.0, 6.0, 6.5, 7.5, 8.0];
    String credit(double h) {
      if (_p.validate() != null) return '—';
      final c = computeDayWorkCredit(
        actualHours: h,
        hoursPerWorkDay: 8,
        minPercent: _p.minPercent,
        decimalWorkDayEnabled: _p.decimal,
        minHalfDayHours: _p.minHalfHours,
      );
      return c == c.roundToDouble() ? c.toInt().toString() : c.toString().replaceAll('.', ',');
    }

    String h(double v) => v == v.roundToDouble() ? '${v.toInt()}h' : '${v.toString().replaceAll('.', ',')}h';
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(10), border: Border.all(color: SboxColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ví dụ với giờ chuẩn 8 giờ / công'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in hours)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: SboxColors.border)),
              child: Column(children: [
                Text(tr('Làm ${h(x)}'), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                Text(tr('${credit(x)} công'), style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              ]),
            ),
        ]),
      ]),
    );
  }

  // ─── Chấm công bù & duyệt ──────────────────────────────────────

  Widget _approvalSection(bool edit) {
    const levelText = {
      1: 'Quản lý trực tiếp duyệt là xong',
      2: 'Quản lý trực tiếp, sau đó quản lý cấp cao',
      3: 'Quản lý trực tiếp, trưởng phòng, rồi quản trị',
    };
    Widget levels(int value, ValueChanged<int> onChanged) => SettingsSegment<int>(
          value: value,
          options: const [(1, '1 cấp'), (2, '2 cấp'), (3, '3 cấp')],
          onChanged: edit ? onChanged : (_) {},
        );
    return SettingsSection(
      title: 'Chấm công bù & quy trình duyệt',
      subtitle: 'Áp dụng cho yêu cầu mới; yêu cầu đang chờ giữ quy trình lúc gửi',
      icon: Icons.approval_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Cho phép xin sửa / bổ sung công',
          help: _p.allowCorrection ? 'Nhân viên gửi yêu cầu bổ sung lần chấm bị thiếu' : 'Nhân viên không gửi được yêu cầu sửa công',
          control: Switch(value: _p.allowCorrection, onChanged: edit ? (v) => _set(() => _p.allowCorrection = v) : null),
        ),
        if (_p.allowCorrection)
          SettingsTile(
            label: 'Duyệt yêu cầu sửa công',
            help: levelText[_p.correctionLevels],
            control: levels(_p.correctionLevels, (v) => _set(() => _p.correctionLevels = v)),
          ),
        SettingsTile(
          label: 'Duyệt đơn nghỉ phép',
          help: levelText[_p.leaveLevels],
          control: levels(_p.leaveLevels, (v) => _set(() => _p.leaveLevels = v)),
        ),
      ],
    );
  }
}
