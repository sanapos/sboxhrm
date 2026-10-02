import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../utils/branch_filter_helper.dart';
import '../../utils/vn_search.dart';
import '../../widgets/settings/settings_page.dart' show settingsMoney, settingsNum;
import '../../widgets/sbox/sbox_ui.dart';
import 'al_policy.dart';

/// Một dòng phép năm (GET /api/annual-leave/summary).
class AlRow {
  AlRow(this.m);
  final Map<String, dynamic> m;
  double _d(String k) => (m[k] as num?)?.toDouble() ?? 0;
  String get id => '${m['employeeId']}';
  String get code => '${m['code'] ?? ''}';
  String get name => '${m['name'] ?? ''}';
  String? get department => m['department']?.toString();
  String? get branchId => m['branchId']?.toString();
  DateTime? get joinDate => DateTime.tryParse('${m['joinDate'] ?? ''}');
  DateTime? get resignDate => DateTime.tryParse('${m['resignationDate'] ?? ''}');
  bool get hasProfile => m['hasSalaryProfile'] == true;
  bool get eligible => m['eligible'] == true;
  double get baseDays => _d('baseDays');
  double get seniority => _d('seniorityDays');
  int get months => (m['months'] as num?)?.toInt() ?? 0;
  double get entitled => _d('entitled');
  double get carry => _d('carry');
  double get carryExpired => _d('carryExpired');
  DateTime? get carryExpiresOn => DateTime.tryParse('${m['carryExpiresOn'] ?? ''}');
  double get adjust => _d('adjust');
  double get used => _d('used');
  double get pending => _d('pending');
  double get paidOutDays => _d('paidOutDays');
  double get paidOutAmount => _d('paidOutAmount');
  double get remaining => _d('remaining');
  double get available => _d('available');
  double get dailyRate => _d('dailyRate');
  double get remainingValue => remaining > 0 ? remaining * dailyRate : 0;
  bool get resigned => resignDate != null;
  bool get needsPayout => resigned && remaining > 0;
}

String _days(double v) => '${settingsNum(v)} ngày';
String _money(num v) => '${settingsMoney(v)}đ';
String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Phép năm: quản lý xem cả cửa hàng (theo dõi, báo cáo, chốt năm, trả tiền); nhân viên xem phép của mình.
class AnnualLeaveScreen extends StatefulWidget {
  const AnnualLeaveScreen({super.key, this.managerOverride, this.myEmployeeId, this.initialYear});
  final bool? managerOverride;
  final String? myEmployeeId;
  final int? initialYear;

  @override
  State<AnnualLeaveScreen> createState() => _AnnualLeaveScreenState();
}

enum _F { all, remaining, payout, expiring, ineligible }

class _AnnualLeaveScreenState extends State<AnnualLeaveScreen> {
  final _api = ApiService();
  late int _year = widget.initialYear ?? DateTime.now().year;
  List<AlRow> _rows = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  _F _f = _F.all;

  bool _perm(bool Function(PermissionProvider p) f) {
    try {
      return f(Provider.of<PermissionProvider>(context, listen: false));
    } catch (_) {
      return false;
    }
  }

  bool get _manager =>
      widget.managerOverride ??
      _perm((p) => p.canApprove('Leave') || p.canView('LeaveReport') || p.canEdit('SalarySettings'));
  bool get _canEdit => widget.managerOverride ?? _perm((p) => p.canEdit('Leave') || p.canEdit('SalarySettings'));
  bool get _canPay => widget.managerOverride ?? _perm((p) => p.canEdit('Payroll') || p.canEdit('SalarySettings'));

  String? get _myEmployeeId {
    if (widget.myEmployeeId != null) return widget.myEmployeeId;
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.employeeId;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    BranchSession.instance.addListener(_onBranch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    if (!_manager) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await Future.wait([_api.getAnnualLeaveSummary(_year), _api.getBranchesForSelect()]);
    if (!mounted) return;
    final res = r[0];
    final br = r[1];
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is List) {
        _rows = [for (final x in (res['data'] as List).whereType<Map>()) AlRow(Map<String, dynamic>.from(x))];
      } else {
        _error = res['message']?.toString() ?? 'Không tải được phép năm.';
      }
      _branches = br['data'] is List ? [for (final b in (br['data'] as List).whereType<Map>()) Map<String, dynamic>.from(b)] : const [];
    });
  }

  List<AlRow> get _inBranch {
    final b = BranchFilterHelper.viewBranchId;
    if (b == null || _branches.length < 2) return _rows;
    final ids = BranchFilterHelper.expandBranchIds(b, _branches);
    return _rows.where((r) => ids.contains(r.branchId)).toList();
  }

  List<AlRow> get _shown => _inBranch.where((r) {
        final ok = switch (_f) {
          _F.all => r.eligible || r.remaining != 0,
          _F.remaining => r.remaining > 0,
          _F.payout => r.needsPayout,
          _F.expiring => r.carry - r.carryExpired > 0 && r.carryExpiresOn != null && r.carryExpired == 0,
          _F.ineligible => !r.eligible,
        };
        if (!ok) return false;
        return _q.isEmpty || vnContains(r.name, _q) || vnContains(r.code, _q) || vnContains(r.department ?? '', _q);
      }).toList();

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(tr(m)), backgroundColor: error ? SboxColors.danger : null, behavior: SnackBarBehavior.floating));

  // ─── Hành động ─────────────────────────────────────────────────

  Future<void> _openPolicy() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: AnnualLeavePolicyScreen())));
    _load();
  }

  Future<void> _adjust(AlRow r) async {
    final days = TextEditingController();
    final note = TextEditingController();
    var add = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Điều chỉnh phép năm $_year')),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${r.name} · còn ${_days(r.remaining)}', style: SboxType.bodyStrong()),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(tr('Cộng phép')), icon: const Icon(Icons.add_rounded)),
                  ButtonSegment(value: false, label: Text(tr('Trừ phép')), icon: const Icon(Icons.remove_rounded)),
                ],
                selected: {add},
                onSelectionChanged: (s) => set(() => add = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: days,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Số ngày'), border: const OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: InputDecoration(
                  labelText: tr('Lý do *'),
                  hintText: tr('VD: phép tồn trước khi dùng SBOX, thưởng phép…'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    final d = double.tryParse(days.text.trim().replaceAll(',', '.')) ?? 0;
    final n = note.text.trim();
    days.dispose();
    note.dispose();
    if (ok != true) return;
    if (d <= 0 || n.isEmpty) return _toast('Nhập số ngày và lý do.', error: true);
    final res = await _api.adjustAnnualLeave(r.id, _year, add ? d : -d, n);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _toast('Đã điều chỉnh phép năm của ${r.name}');
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'Không điều chỉnh được.', error: true);
    }
  }

  Future<DateTime?> _pickMonth(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(_year - 1),
      lastDate: DateTime(_year + 2, 12, 31),
      helpText: tr('Chọn tháng lương nhận tiền phép'),
    );
    return d == null ? null : DateTime(d.year, d.month, 1);
  }

  Future<void> _payout(List<AlRow> rows) async {
    final list = rows.where((r) => r.remaining > 0).toList();
    if (list.isEmpty) return _toast('Không còn ngày phép để trả tiền.', error: true);
    var month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final total = list.fold<double>(0, (a, r) => a + r.remainingValue);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Trả tiền phép năm $_year')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in list.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text('${r.name} · ${_days(r.remaining)}')),
                    Text(_money(r.remainingValue), style: SboxType.bodyStrong()),
                  ]),
                ),
              if (list.length > 8) Text(tr('… và ${list.length - 8} người khác'), style: SboxType.smallStyle()),
              const Divider(),
              Row(children: [
                Expanded(child: Text(tr('Tổng'), style: SboxType.bodyStrong())),
                Text(_money(total), style: SboxType.titleStyle(SboxColors.brand700)),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final m = await _pickMonth(month);
                  if (m != null) set(() => month = m);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(tr('Cộng vào bảng lương tháng ${month.month}/${month.year}')),
              ),
              const SizedBox(height: 6),
              Text(tr('Tiền phép là thu nhập chịu thuế TNCN, hiện ở cột «Tiền phép năm» của bảng lương.'), style: SboxType.captionStyle()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Trả tiền'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _api.payoutAnnualLeave(_year, [for (final r in list) {'employeeId': r.id}], month);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _toast('Đã ghi tiền phép cho ${list.length} nhân viên vào bảng lương tháng ${month.month}/${month.year}');
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'Không trả được tiền phép.', error: true);
    }
  }

  Future<void> _closeYear() async {
    final pv = await _api.closeAnnualLeaveYear(_year, apply: false);
    if (!mounted) return;
    if (pv['isSuccess'] != true || pv['data'] is! Map) {
      return _toast(pv['message']?.toString() ?? 'Không xem trước được.', error: true);
    }
    final data = Map<String, dynamic>.from(pv['data'] as Map);
    final closed = data['closed'] == true;
    final rows = [for (final x in (data['rows'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(x)];
    double sum(String k) => rows.fold<double>(0, (a, r) => a + ((r[k] as num?)?.toDouble() ?? 0));
    var month = DateTime(_year + 1, 1, 1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr(closed ? 'Phép năm $_year đã chốt' : 'Chốt phép năm $_year')),
          content: SizedBox(
            width: 520,
            height: 440,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                SboxStatusChip(label: 'Chuyển sang ${_year + 1}: ${_days(sum('carry'))}', tone: SboxTone.brand),
                SboxStatusChip(label: 'Trả tiền: ${_days(sum('payoutDays'))} · ${_money(sum('payoutAmount'))}', tone: SboxTone.success),
                if (sum('lost') > 0) SboxStatusChip(label: 'Hủy: ${_days(sum('lost'))}', tone: SboxTone.warning),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Text(tr('Không ai còn phép năm $_year.')))
                    : ListView(children: [
                        for (final r in rows)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${r['name']} · còn ${_days((r['remaining'] as num).toDouble())}'),
                            subtitle: Text(tr('${r['reason']}'
                                '${(r['carry'] as num) > 0 ? ' · chuyển ${settingsNum(r['carry'] as num)}' : ''}'
                                '${(r['payoutDays'] as num) > 0 ? ' · trả ${_money(r['payoutAmount'] as num)}' : ''}')),
                          ),
                      ]),
              ),
              if (!closed && sum('payoutDays') > 0)
                OutlinedButton.icon(
                  onPressed: () async {
                    final m = await _pickMonth(month);
                    if (m != null) set(() => month = m);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(tr('Tiền phép vào bảng lương tháng ${month.month}/${month.year}')),
                ),
            ]),
          ),
          actions: closed
              ? [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Đóng'))),
                  if (_canPay)
                    TextButton(
                      onPressed: () async {
                        final r = await _api.reopenAnnualLeaveYear(_year);
                        if (ctx.mounted) Navigator.pop(ctx, false);
                        if (mounted) {
                          _toast(r['isSuccess'] == true ? 'Đã mở lại phép năm $_year' : (r['message']?.toString() ?? 'Không mở lại được'),
                              error: r['isSuccess'] != true);
                          _load();
                        }
                      },
                      child: Text(tr('Mở lại năm')),
                    ),
                ]
              : [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Chốt năm'))),
                ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _api.closeAnnualLeaveYear(_year, payrollMonth: month, apply: true);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _toast('Đã chốt phép năm $_year');
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'Không chốt được.', error: true);
    }
  }

  Future<void> _exportCsv() async {
    final rows = _shown;
    final lines = [
      'Mã NV,Họ tên,Phòng ban,Được hưởng,Chuyển sang,Điều chỉnh,Đã nghỉ,Chờ duyệt,Đã trả tiền,Còn lại,Tiền 1 ngày,Giá trị còn lại',
      for (final r in rows)
        [
          r.code,
          '"${r.name}"',
          '"${r.department ?? ''}"',
          settingsNum(r.entitled),
          settingsNum(r.carry - r.carryExpired),
          settingsNum(r.adjust),
          settingsNum(r.used),
          settingsNum(r.pending),
          settingsNum(r.paidOutDays),
          settingsNum(r.remaining),
          r.dailyRate.round(),
          r.remainingValue.round(),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _toast('Đã sao chép báo cáo ${rows.length} nhân viên (dán vào Excel)');
  }

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Phép năm')),
        actions: [
          IconButton(
            tooltip: tr('Năm trước'),
            onPressed: () {
              setState(() => _year--);
              _load();
            },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Center(child: Text('$_year', style: SboxType.titleStyle())),
          IconButton(
            tooltip: tr('Năm sau'),
            onPressed: () {
              setState(() => _year++);
              _load();
            },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (_manager && _canEdit) IconButton(tooltip: tr('Chính sách phép năm'), onPressed: _openPolicy, icon: const Icon(Icons.tune_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: !_manager
          ? (_myEmployeeId == null
              ? const SboxEmptyState(icon: Icons.person_off_outlined, title: 'Tài khoản chưa liên kết hồ sơ nhân viên')
              : AnnualLeaveDetail(employeeId: _myEmployeeId!, year: _year, api: _api))
          : _loading
              ? const SboxLoading(message: 'Đang tính phép năm…')
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
                              constraints: const BoxConstraints(maxWidth: 1150),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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

  Widget _metrics(bool narrow) {
    final rows = _inBranch;
    final eligible = rows.where((r) => r.eligible).toList();
    final remain = eligible.fold<double>(0, (a, r) => a + (r.remaining > 0 ? r.remaining : 0));
    final value = eligible.fold<double>(0, (a, r) => a + r.remainingValue);
    final used = eligible.fold<double>(0, (a, r) => a + r.used);
    final payout = rows.where((r) => r.needsPayout).length;
    Widget m(_F f, String label, String v, IconData icon, Color c) {
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
                Text(v, style: SboxType.titleStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(tr(label), style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    final tiles = [
      m(_F.all, 'Đã nghỉ phép năm ($_year)', _days(used), Icons.beach_access_outlined, SboxColors.brand600),
      m(_F.remaining, 'Còn lại · ${eligible.length} người hưởng', _days(remain), Icons.event_available_outlined, SboxColors.success),
      m(_F.remaining, 'Giá trị phép còn lại', _money(value), Icons.payments_outlined, SboxColors.violet),
      m(_F.payout, 'Nghỉ việc chưa trả tiền phép', '$payout', Icons.person_remove_outlined, SboxColors.warning),
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
        hintText: tr('Tìm nhân viên'),
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
    final payoutRows = _inBranch.where((r) => r.needsPayout).toList();
    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      SboxButton.ghost(label: 'Sao chép báo cáo', icon: Icons.copy_all_rounded, size: SboxButtonSize.sm, onPressed: _exportCsv),
      if (_canPay && payoutRows.isNotEmpty)
        SboxButton.secondary(label: 'Trả tiền phép nghỉ việc (${payoutRows.length})', icon: Icons.payments_outlined, size: SboxButtonSize.sm, onPressed: () => _payout(payoutRows)),
      if (_canPay) SboxButton(label: 'Chốt phép năm $_year', icon: Icons.event_repeat_rounded, size: SboxButtonSize.sm, onPressed: _closeYear),
    ]);
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(_F.all, 'Tất cả'),
        chip(_F.remaining, 'Còn phép'),
        chip(_F.expiring, 'Phép chuyển sắp hết hạn'),
        chip(_F.payout, 'Nghỉ việc còn phép'),
        chip(_F.ineligible, 'Không thuộc diện'),
      ]),
    );
    if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, const SizedBox(height: 8), chips, const SizedBox(height: 8), actions]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [SizedBox(width: 300, child: search), const SizedBox(width: 12), Expanded(child: chips)]),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerRight, child: actions),
    ]);
  }

  Widget _list(bool narrow) {
    final rows = _shown;
    if (rows.isEmpty) {
      return const SboxCard(child: SboxEmptyState(icon: Icons.beach_access_outlined, title: 'Không có nhân viên phù hợp'));
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
      child: Column(children: [
        if (!narrow) _headerRow(),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0 || !narrow) const Divider(height: 1, indent: 16, endIndent: 16),
          _row(rows[i], narrow),
        ],
      ]),
    );
  }

  static const _cols = ['Được hưởng', 'Chuyển sang', 'Điều chỉnh', 'Đã nghỉ', 'Chờ duyệt', 'Trả tiền', 'Còn lại'];

  Widget _headerRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(children: [
          Expanded(child: Text(tr('Nhân viên'), style: SboxType.captionStyle())),
          for (final c in _cols) SizedBox(width: 86, child: Text(tr(c), textAlign: TextAlign.right, style: SboxType.captionStyle())),
          const SizedBox(width: 40),
        ]),
      );

  Widget _row(AlRow r, bool narrow) {
    final carryNow = r.carry - r.carryExpired;
    final chips = <Widget>[
      if (!r.hasProfile) const SboxStatusChip(label: 'Chưa thiết lập lương', tone: SboxTone.warning)
      else if (!r.eligible) const SboxStatusChip(label: 'Không thuộc diện', tone: SboxTone.neutral),
      if (r.resigned) SboxStatusChip(label: 'Nghỉ việc ${_dmy(r.resignDate!)}', tone: r.needsPayout ? SboxTone.danger : SboxTone.neutral),
      if (r.months > 0 && r.months < 12 && r.eligible) SboxStatusChip(label: '${r.months} tháng', tone: SboxTone.neutral),
      if (r.seniority > 0) SboxStatusChip(label: '+${settingsNum(r.seniority)} thâm niên', tone: SboxTone.violet),
      if (carryNow > 0 && r.carryExpiresOn != null) SboxStatusChip(label: 'Phép chuyển hết hạn ${_dmy(r.carryExpiresOn!).substring(0, 5)}', tone: SboxTone.warning),
    ];
    final remainColor = r.remaining < 0 ? SboxColors.danger : (r.remaining > 0 ? SboxColors.success : SboxColors.textMuted);
    final menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) => switch (v) {
        'detail' => _detail(r),
        'adjust' => _adjust(r),
        'payout' => _payout([r]),
        _ => null,
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'detail', child: Text(tr('Xem chi tiết'))),
        if (_canEdit) PopupMenuItem(value: 'adjust', child: Text(tr('Điều chỉnh phép'))),
        if (_canPay && r.remaining > 0) PopupMenuItem(value: 'payout', child: Text(tr('Trả tiền phép còn lại'))),
      ],
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.name, style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text([r.code, if (r.department != null && r.department!.isNotEmpty) r.department!].join(' · '), style: SboxType.captionStyle()),
      if (chips.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 6, runSpacing: 6, children: chips)],
    ]);
    if (narrow) {
      return InkWell(
        onTap: () => _detail(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                info,
                const SizedBox(height: 6),
                Text(tr('Được ${settingsNum(r.entitled + carryNow + r.adjust)} · đã nghỉ ${settingsNum(r.used)}'
                    '${r.pending > 0 ? ' · chờ ${settingsNum(r.pending)}' : ''}'), style: SboxType.smallStyle()),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(settingsNum(r.remaining), style: SboxType.headlineStyle(remainColor)),
              Text(tr('còn lại'), style: SboxType.captionStyle()),
            ]),
            menu,
          ]),
        ),
      );
    }
    Widget cell(double v, {Color? c, bool strong = false}) => SizedBox(
          width: 86,
          child: Text(v == 0 ? '–' : settingsNum(v),
              textAlign: TextAlign.right, style: strong ? SboxType.bodyStrong(c ?? SboxColors.text) : SboxType.bodyStyle(c ?? SboxColors.textSecondary)),
        );
    return InkWell(
      onTap: () => _detail(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
        child: Row(children: [
          Expanded(child: info),
          cell(r.entitled),
          cell(carryNow),
          cell(r.adjust),
          cell(r.used),
          cell(r.pending, c: SboxColors.warningText),
          cell(r.paidOutDays),
          cell(r.remaining, c: remainColor, strong: true),
          menu,
        ]),
      ),
    );
  }

  Future<void> _detail(AlRow r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: AnnualLeaveDetail(employeeId: r.id, year: _year, api: _api, canEdit: _canEdit, onChanged: _load),
      ),
    );
  }
}

/// Chi tiết phép năm một nhân viên: cách tính, đơn nghỉ, điều chỉnh / chuyển / trả tiền.
class AnnualLeaveDetail extends StatefulWidget {
  const AnnualLeaveDetail({super.key, required this.employeeId, required this.year, required this.api, this.canEdit = false, this.onChanged});
  final String employeeId;
  final int year;
  final ApiService api;
  final bool canEdit;
  final VoidCallback? onChanged;

  @override
  State<AnnualLeaveDetail> createState() => _AnnualLeaveDetailState();
}

class _AnnualLeaveDetailState extends State<AnnualLeaveDetail> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnnualLeaveDetail old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year || old.employeeId != widget.employeeId) _load();
  }

  Future<void> _load() async {
    final r = await widget.api.getAnnualLeaveDetail(widget.employeeId, widget.year);
    if (!mounted) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) {
        _d = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được phép năm.';
      }
    });
  }

  static const _kind = {'adjust': 'Điều chỉnh', 'carry': 'Chuyển từ năm trước', 'payout': 'Trả tiền phép', 'opening': 'Số dư đầu'};
  static const _type = {'AnnualLeave': 'Phép năm', 'SickLeave': 'Ốm (trừ phép năm)'};
  static const _status = {'Approved': 'Đã duyệt', 'Pending': 'Chờ duyệt'};

  @override
  Widget build(BuildContext context) {
    if (_error != null) return SboxEmptyState(icon: Icons.error_outline_rounded, title: _error!);
    final d = _d;
    if (d == null) return const SboxLoading();
    final r = AlRow(Map<String, dynamic>.from(d['summary'] as Map));
    final leaves = [for (final x in (d['leaves'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(x)];
    final entries = [for (final x in (d['entries'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(x)]
        .where((e) => e['kind'] != 'mark')
        .toList();
    Widget line(String l, String v, {bool strong = false, Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(tr(l), style: strong ? SboxType.bodyStrong() : SboxType.smallStyle())),
            Text(v, style: strong ? SboxType.titleStyle(c ?? SboxColors.brand700) : SboxType.bodyStyle(c ?? SboxColors.text)),
          ]),
        );
    final carryNow = r.carry - r.carryExpired;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Text('${r.name} · ${widget.year}', style: SboxType.titleStyle()),
      Text([r.code, if (r.joinDate != null) 'vào làm ${_dmy(r.joinDate!)}', if (r.resignDate != null) 'nghỉ việc ${_dmy(r.resignDate!)}'].join(' · '),
          style: SboxType.captionStyle()),
      const SizedBox(height: 12),
      if (!r.eligible)
        SettingsNoteBoxLite(r.hasProfile
            ? 'Không thuộc diện hưởng phép năm theo chính sách cửa hàng (chỉ áp dụng lương tháng).'
            : 'Chưa có thiết lập lương — chưa có quỹ phép năm.'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(12), border: Border.all(color: SboxColors.brand100)),
        child: Column(children: [
          line('Phép năm', _days(r.baseDays)),
          if (r.seniority > 0) line('Thâm niên', '+ ${_days(r.seniority)}'),
          if (r.months < 12 && r.eligible) line('Làm ${r.months}/12 tháng (làm tròn)', '= ${_days(r.entitled)}'),
          if (r.carry > 0)
            line('Chuyển từ năm trước${r.carryExpiresOn != null ? ' (dùng trước ${_dmy(r.carryExpiresOn!)})' : ''}', '+ ${_days(r.carry)}'),
          if (r.carryExpired > 0) line('Phép chuyển quá hạn', '− ${_days(r.carryExpired)}', c: SboxColors.dangerText),
          if (r.adjust != 0) line('Điều chỉnh', '${r.adjust > 0 ? '+' : '−'} ${_days(r.adjust.abs())}'),
          line('Đã nghỉ', '− ${_days(r.used)}'),
          if (r.paidOutDays > 0) line('Đã trả tiền (${_money(r.paidOutAmount)})', '− ${_days(r.paidOutDays)}'),
          const Divider(height: 16),
          line('Còn lại', _days(r.remaining), strong: true, c: r.remaining < 0 ? SboxColors.danger : null),
          if (r.pending > 0) line('Đơn chờ duyệt', '− ${_days(r.pending)} (còn xin được ${settingsNum(r.available)})'),
          if (r.dailyRate > 0 && r.remaining > 0) line('Giá trị nếu trả tiền (${_money(r.dailyRate)}/ngày)', _money(r.remainingValue)),
        ]),
      ),
      if (carryNow > 0 && r.carryExpiresOn != null && r.carryExpired == 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SettingsNoteBoxLite('${_days(carryNow)} chuyển từ năm trước cần dùng trước ${_dmy(r.carryExpiresOn!)}, quá hạn sẽ bị hủy.'),
        ),
      const SizedBox(height: 16),
      Text(tr('Đơn nghỉ trừ phép năm'), style: SboxType.titleSmStyle()),
      if (leaves.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Chưa có đơn nào.'), style: SboxType.smallStyle())),
      for (final l in leaves)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(l['status'] == 'Approved' ? Icons.check_circle_outline_rounded : Icons.hourglass_top_rounded,
              color: l['status'] == 'Approved' ? SboxColors.success : SboxColors.warning),
          title: Text('${_dmy(DateTime.parse('${l['startDate']}'))}'
              '${'${l['startDate']}'.substring(0, 10) == '${l['endDate']}'.substring(0, 10) ? '' : ' – ${_dmy(DateTime.parse('${l['endDate']}'))}'}'
              '${l['halfShift'] == true ? ' (nửa ca)' : ''}'),
          subtitle: Text(tr('${_type[l['type']] ?? l['type']} · ${_status[l['status']] ?? l['status']}'
              '${(l['reason'] ?? '').toString().isNotEmpty ? ' · ${l['reason']}' : ''}')),
          trailing: Text(_days((l['days'] as num).toDouble()), style: SboxType.bodyStrong()),
        ),
      if (entries.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(tr('Điều chỉnh, chuyển phép, trả tiền'), style: SboxType.titleSmStyle()),
        for (final e in entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('${_kind[e['kind']] ?? e['kind']} · ${(e['days'] as num) > 0 ? '+' : ''}${settingsNum(e['days'] as num)} ngày'
                '${e['amount'] != null ? ' · ${_money(e['amount'] as num)}' : ''}')),
            subtitle: Text(tr([
              '${e['note'] ?? ''}'.replaceFirst(RegExp(r'^close:\d+ '), ''),
              if (e['payrollMonth'] != null) 'lương tháng ${DateTime.parse('${e['payrollMonth']}').month}/${DateTime.parse('${e['payrollMonth']}').year}',
            ].where((x) => x.isNotEmpty).join(' · '))),
            trailing: widget.canEdit && e['kind'] != 'carry'
                ? IconButton(
                    tooltip: tr('Xóa'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final res = await widget.api.deleteAnnualLeaveEntry('${e['id']}');
                      if (res['isSuccess'] == true) {
                        widget.onChanged?.call();
                        _load();
                      }
                    },
                  )
                : null,
          ),
      ],
    ]);
  }
}

class SettingsNoteBoxLite extends StatelessWidget {
  const SettingsNoteBoxLite(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: SboxColors.warningText),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: SboxType.smallStyle(SboxColors.warningText))),
        ]),
      );
}
