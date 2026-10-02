import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../utils/branch_filter_helper.dart';
import '../../utils/vn_search.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/settings/settings_page.dart' show settingsNum;
import '../../widgets/sbox/sbox_ui.dart';
import 'sl_common.dart';
import 'sl_editor.dart';
import 'sl_model.dart';

/// Thiết lập lương: mỗi nhân viên một hồ sơ lương (loại lương, mức lương, tăng ca, BHXH, chấm công).
class SalaryV2Screen extends StatefulWidget {
  const SalaryV2Screen({super.key, this.canEditOverride});

  /// Bỏ qua kiểm quyền (dùng cho test).
  final bool? canEditOverride;

  @override
  State<SalaryV2Screen> createState() => _SalaryV2ScreenState();
}

enum _F { all, missing, done, monthly, daily, shift, hourly, insured }

class _SalaryV2ScreenState extends State<SalaryV2Screen> {
  final _api = ApiService();
  late SlContext _ctx = SlContext(api: _api);
  List<SlEmployee> _all = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;
  bool _partial = false;
  String _q = '';
  _F _f = _F.all;

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('SalarySettings');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    BranchSession.instance.addListener(_onBranch);
    _load();
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_onBranch);
    super.dispose();
  }

  void _onBranch() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait<dynamic>([
        _api.getEmployeesForSelect(),
        _api.getShifts(),
        _api.getAllowanceSettings(),
        _api.getInsuranceSettings(),
        _api.getBranchesForSelect(),
        _api.getSalarySettings(),
        _api.getEmployeeSalaryProfilesBulk(),
      ]);
      List<Map<String, dynamic>> maps(dynamic v) => [for (final x in (v is List ? v : const [])) if (x is Map) Map<String, dynamic>.from(x)];
      final bulk = r[6] as Map<String, dynamic>?;
      final emps = maps(r[0]);
      final list = <SlEmployee>[];
      for (final e in emps) {
        final p = bulk?['${e['id'] ?? ''}'.toLowerCase()];
        list.add(SlEmployee(e, p is Map ? Map<String, dynamic>.from(p) : null));
      }
      list.sort((a, b) {
        if (a.configured != b.configured) return a.configured ? 1 : -1;
        return a.name.compareTo(b.name);
      });
      final br = r[4];
      if (!mounted) return;
      setState(() {
        _ctx = SlContext(
          api: _api,
          shifts: maps(r[1]),
          allowances: maps(r[2]),
          insurance: r[3] is Map ? Map<String, dynamic>.from(r[3] as Map) : const {},
          store: r[5] is Map ? Map<String, dynamic>.from(r[5] as Map) : {},
        );
        _branches = br is Map && br['data'] is List ? maps(br['data']) : const [];
        _all = list;
        // Không tải được hồ sơ lương → không kết luận «Chưa thiết lập».
        _partial = bulk == null && emps.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được dữ liệu lương.';
        });
      }
    }
  }

  List<SlEmployee> get _inBranch {
    final b = BranchFilterHelper.viewBranchId;
    if (b == null || _branches.length < 2) return _all;
    final ids = BranchFilterHelper.expandBranchIds(b, _branches);
    return _all.where((e) => ids.contains(e.branchId)).toList();
  }

  List<SlEmployee> get _shown {
    return _inBranch.where((e) {
      final ok = switch (_f) {
        _F.all => true,
        _F.missing => !e.configured,
        _F.done => e.configured,
        _F.monthly => e.configured && e.kind == SalaryKind.monthly,
        _F.daily => e.configured && e.kind == SalaryKind.daily,
        _F.shift => e.configured && e.kind == SalaryKind.shift,
        _F.hourly => e.configured && e.kind == SalaryKind.hourly,
        _F.insured => e.configured && SalaryDraft.fromBenefit(e.benefit).insurance != InsuranceKind.none,
      };
      if (!ok) return false;
      if (_q.trim().isEmpty) return true;
      return vnContains(e.name, _q) || vnContains(e.code, _q) || vnContains(e.department ?? '', _q);
    }).toList();
  }

  Future<void> _open(SlEmployee e) async {
    if (await showSalaryEditor(context, _ctx, e, canEdit: _canEdit, onEditStoreRates: _canEdit ? _editStoreRates : null)) {
      if (mounted) slToast(context, 'Đã lưu thiết lập lương của ${e.name}');
      _load();
    }
  }

  // ─── Hệ số tăng ca cửa hàng ────────────────────────────────────

  Future<void> _editStoreRates() async {
    final w = TextEditingController(text: settingsNum(_ctx.otRate('overtimeRate', 1.5)));
    final e = TextEditingController(text: settingsNum(_ctx.otRate('weekendRate', 2.0)));
    final h = TextEditingController(text: settingsNum(_ctx.otRate('holidayRate', 3.0)));
    Widget f(String label, String hint, TextEditingController c) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hệ số tăng ca theo luật')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Áp dụng cho mọi nhân viên chọn «Theo luật». Tiền tăng ca = giờ × đơn giá giờ × hệ số.'), style: SboxType.smallStyle()),
            const SizedBox(height: 16),
            f('Ngày thường', 'Luật lao động: tối thiểu 1,5', w),
            f('Ngày nghỉ hằng tuần', 'Luật lao động: tối thiểu 2', e),
            f('Ngày lễ, Tết', 'Luật lao động: tối thiểu 3', h),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    double p(TextEditingController c, double fb) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      return v == null || v <= 0 ? fb : v.clamp(1.0, 10.0);
    }

    final payload = {
      ..._ctx.store,
      'overtimeRate': p(w, 1.5),
      'weekendRate': p(e, 2.0),
      'holidayRate': p(h, 3.0),
    };
    for (final c in [w, e, h]) {
      c.dispose();
    }
    if (ok != true || !mounted) return;
    final res = await _api.saveSalarySettings(payload);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() => _ctx.store = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : payload);
      slToast(context, 'Đã lưu hệ số tăng ca');
    } else {
      slToast(context, res['message']?.toString() ?? 'Không lưu được hệ số tăng ca', error: true);
    }
  }

  // ─── Sao chép thiết lập ────────────────────────────────────────

  Future<void> _copyFrom(SlEmployee src) async {
    final picked = <String>{};
    var q = '';
    final targets = _inBranch.where((e) => e.id != src.id).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final shown = targets.where((e) => q.isEmpty || vnContains(e.name, q) || vnContains(e.code, q)).toList();
        final missing = targets.where((e) => !e.configured).map((e) => e.id).toSet();
        return AlertDialog(
          title: Text(tr('Sao chép thiết lập của ${src.name}')),
          content: SizedBox(
            width: 460,
            height: 480,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('${salarySummary(src)} · ${src.kind.label}. Nhân viên được chọn sẽ có thiết lập giống hệt (mức lương, tăng ca, BHXH, chấm công).'),
                  style: SboxType.smallStyle()),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => set(() => q = v),
                decoration: InputDecoration(
                  hintText: tr('Tìm nhân viên'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Row(children: [
                TextButton(onPressed: () => set(() => picked.addAll(missing)), child: Text(tr('Chọn người chưa thiết lập (${missing.length})'))),
                const Spacer(),
                if (picked.isNotEmpty) TextButton(onPressed: () => set(picked.clear), child: Text(tr('Bỏ chọn'))),
              ]),
              Expanded(
                child: ListView(children: [
                  for (final e in shown)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: picked.contains(e.id),
                      onChanged: (v) => set(() => v == true ? picked.add(e.id) : picked.remove(e.id)),
                      title: Text(e.name),
                      subtitle: Text('${e.code} · ${salarySummary(e)}'),
                    ),
                ]),
              ),
              if (picked.any((id) => targets.firstWhere((e) => e.id == id).configured))
                const SettingsNoteInline('Nhân viên đã có thiết lập sẽ bị ghi đè.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(tr('Sao chép cho ${picked.length} người'))),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    final draft = SalaryDraft.fromBenefit(src.benefit, defaultHours: _ctx.stdHours);
    var done = 0;
    final errors = <String>[];
    for (final e in targets.where((e) => picked.contains(e.id))) {
      final d = draft.copy()..original = e.benefit ?? {...draft.original};
      // Hồ sơ của người nhận: giữ trường riêng của họ nếu đã có, tạo mới nếu chưa.
      final err = await saveSalaryFor(_ctx, e, d, forceNew: !e.configured);
      if (err == null) {
        done++;
      } else {
        errors.add('${e.name}: $err');
      }
    }
    if (!mounted) return;
    slToast(context, errors.isEmpty ? 'Đã sao chép cho $done nhân viên' : 'Sao chép được $done, lỗi ${errors.length}: ${errors.first}',
        error: errors.isNotEmpty);
    _load();
  }

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: _loading
          ? const SboxLoading(message: 'Đang tải thiết lập lương…')
          : _error != null
              ? SboxEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  action: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, 16, narrow ? 12 : 24, 40),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _header(narrow),
                            const SizedBox(height: 16),
                            if (_partial) ...[
                              const SettingsNoteInline('Không tải được hồ sơ lương — trạng thái «Chưa thiết lập» có thể chưa đúng. Kéo xuống để tải lại.'),
                              const SizedBox(height: 12),
                            ],
                            _metrics(narrow),
                            const SizedBox(height: 16),
                            _toolbar(narrow),
                            const SizedBox(height: 12),
                            _list(narrow),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(bool narrow) {
    final w = settingsNum(_ctx.otRate('overtimeRate', 1.5));
    final e = settingsNum(_ctx.otRate('weekendRate', 2.0));
    final h = settingsNum(_ctx.otRate('holidayRate', 3.0));
    final title = Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: SboxColors.successSoft, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.request_quote_outlined, color: SboxColors.successText),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Thiết lập lương'), style: SboxType.headlineStyle()),
          Text(tr('Loại lương, mức lương, tăng ca, BHXH và cách chấm công của từng nhân viên.'), style: SboxType.smallStyle()),
        ]),
      ),
    ]);
    final rates = SboxButton.secondary(
      label: 'Hệ số tăng ca ×$w · ×$e · ×$h',
      icon: Icons.more_time_rounded,
      onPressed: _canEdit ? _editStoreRates : null,
    );
    if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), Align(alignment: Alignment.centerLeft, child: rates)]);
    return Row(children: [Expanded(child: title), rates]);
  }

  Widget _metrics(bool narrow) {
    final list = _inBranch;
    final done = list.where((e) => e.configured).length;
    final insured = list.where((e) => e.configured && SalaryDraft.fromBenefit(e.benefit).insurance != InsuranceKind.none).length;
    Widget m(_F f, String label, int n, IconData icon, Color c) {
      final sel = _f == f;
      return InkWell(
        onTap: () => setState(() => _f = sel ? _F.all : f),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? c.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? c : SboxColors.border, width: sel ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$n', style: SboxType.titleStyle()),
                Text(tr(label), style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    final tiles = [
      m(_F.all, 'Nhân viên', list.length, Icons.people_alt_outlined, SboxColors.brand600),
      m(_F.missing, 'Chưa thiết lập', list.length - done, Icons.report_gmailerrorred_rounded, SboxColors.warning),
      m(_F.done, 'Đã thiết lập', done, Icons.check_circle_outline_rounded, SboxColors.success),
      m(_F.insured, 'Có đóng BHXH', insured, Icons.health_and_safety_outlined, SboxColors.violet),
    ];
    if (narrow) {
      return Column(children: [
        Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 8), Expanded(child: tiles[1])]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 8), Expanded(child: tiles[3])]),
      ]);
    }
    return Row(children: [for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: tiles[i])]]);
  }

  Widget _toolbar(bool narrow) {
    final search = TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: InputDecoration(
        hintText: tr('Tìm theo tên, mã nhân viên, phòng ban'),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.border)),
      ),
    );
    Widget chip(_F f, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(label: Text(tr(label)), selected: _f == f, showCheckmark: false, onSelected: (_) => setState(() => _f = f)),
        );
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(_F.all, 'Tất cả'),
        chip(_F.missing, 'Chưa thiết lập'),
        chip(_F.monthly, 'Lương tháng'),
        chip(_F.daily, 'Lương ngày'),
        chip(_F.shift, 'Lương ca'),
        chip(_F.hourly, 'Lương giờ'),
      ]),
    );
    if (narrow) return Column(children: [search, const SizedBox(height: 8), chips]);
    return Row(children: [SizedBox(width: 320, child: search), const SizedBox(width: 12), Expanded(child: chips)]);
  }

  Widget _list(bool narrow) {
    final shown = _shown;
    if (shown.isEmpty) {
      return SboxCard(
        child: SboxEmptyState(
          icon: Icons.person_search_outlined,
          title: _all.isEmpty ? 'Chưa có nhân viên' : 'Không có nhân viên phù hợp',
          message: _all.isEmpty ? 'Thêm nhân viên ở mục Nhân sự trước.' : 'Thử bỏ bớt bộ lọc.',
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
      child: Column(children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          _row(shown[i], narrow),
        ],
      ]),
    );
  }

  Widget _row(SlEmployee e, bool narrow) {
    final d = e.configured ? SalaryDraft.fromBenefit(e.benefit) : null;
    final allowance = _ctx.allowanceTotal(e, 0);
    final daily = _ctx.allowanceTotal(e, 1);
    final chips = <Widget>[
      if (d == null)
        const SboxStatusChip(label: 'Chưa thiết lập', tone: SboxTone.warning, icon: Icons.warning_amber_rounded)
      else ...[
        SboxStatusChip(label: d.kind.label, tone: kindTone(d.kind)),
        if (d.insurance != InsuranceKind.none) const SboxStatusChip(label: 'BHXH', tone: SboxTone.violet),
        SboxStatusChip(label: attendanceLabel(d.attendance), tone: SboxTone.neutral),
        if (e.upcomingFrom != null)
          SboxStatusChip(label: 'Đổi lương ${dmy(e.upcomingFrom!).substring(0, 5)}', tone: SboxTone.warning, icon: Icons.schedule_rounded),
        if (d.shifts.isNotEmpty) SboxStatusChip(label: d.shifts.length == 1 ? d.shifts.first : '${d.shifts.length} ca', tone: SboxTone.neutral),
      ],
    ];
    final sub = [e.code, if (e.department != null && e.department!.isNotEmpty) e.department!, if (e.position != null && e.position!.isNotEmpty) e.position!].join(' · ');
    final amount = Column(crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
      Text(salarySummary(e), style: d == null ? SboxType.bodyStyle(SboxColors.textMuted) : SboxType.bodyStrong()),
      if (allowance > 0 || daily > 0)
        Text(tr('Phụ cấp ${[if (allowance > 0) '${money(allowance)}/tháng', if (daily > 0) '${money(daily)}/ngày'].join(' + ')}'), style: SboxType.captionStyle()),
    ]);
    return InkWell(
      onTap: () => _open(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SlAvatar(e),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(sub, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (narrow && d != null) ...[const SizedBox(height: 4), amount],
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ]),
          ),
          if (!narrow) ...[const SizedBox(width: 12), SizedBox(width: 220, child: amount)],
          PopupMenuButton<String>(
            tooltip: tr('Thao tác'),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => v == 'copy' ? _copyFrom(e) : _open(e),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(tr(_canEdit ? (e.configured ? 'Sửa thiết lập' : 'Thiết lập lương') : 'Xem thiết lập'))),
              if (_canEdit && e.configured) PopupMenuItem(value: 'copy', child: Text(tr('Sao chép cho nhân viên khác'))),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Ghi chú cảnh báo nhỏ (ngoài SettingsPage).
class SettingsNoteInline extends StatelessWidget {
  const SettingsNoteInline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: SboxColors.warningText),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: SboxType.smallStyle(SboxColors.warningText))),
        ]),
      );
}
