import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../departments_v2/dp_common.dart';
import '../hr_finance/hr_fin_common.dart';
import 'ec_forms.dart';

/// Kiểu sự kiện trên dòng thời gian.
class EcKind {
  const EcKind(this.label, this.icon, this.color, this.group);
  final String label;
  final IconData icon;
  final Color color;

  /// work | reward | discipline | paper
  final String group;

  static const all = <String, EcKind>{
    'join': EcKind('Vào làm', Icons.login_rounded, SboxColors.success, 'work'),
    'resign': EcKind('Nghỉ việc', Icons.logout_rounded, SboxColors.slate500, 'work'),
    'transfer': EcKind('Điều chuyển', Icons.swap_horiz_rounded, SboxColors.brand600, 'work'),
    'appointment': EcKind('Bổ nhiệm', Icons.badge_rounded, SboxColors.violet, 'work'),
    'promotion': EcKind('Thăng chức', Icons.trending_up_rounded, SboxColors.success, 'work'),
    'award': EcKind('Khen thưởng', Icons.emoji_events_rounded, SboxColors.warning, 'reward'),
    'bonus': EcKind('Thưởng tiền', Icons.payments_rounded, SboxColors.success, 'reward'),
    'discipline': EcKind('Kỷ luật', Icons.gavel_rounded, SboxColors.danger, 'discipline'),
    'penalty': EcKind('Phạt tiền', Icons.money_off_rounded, SboxColors.danger, 'discipline'),
    'contract': EcKind('Hợp đồng', Icons.description_rounded, SboxColors.brand600, 'paper'),
    'salary': EcKind('Điều chỉnh lương', Icons.price_change_rounded, SboxColors.violet, 'paper'),
    'certificate': EcKind('Bằng cấp', Icons.school_rounded, SboxColors.brand600, 'paper'),
    'handover': EcKind('Bàn giao', Icons.assignment_return_rounded, SboxColors.slate500, 'paper'),
  };

  static EcKind of(String? k) => all[k] ?? const EcKind('Khác', Icons.circle_outlined, SboxColors.slate500, 'paper');
}

/// Quá trình công tác của 1 nhân viên: dòng thời gian gộp + tóm tắt + thêm khen thưởng / kỷ luật / điều chuyển.
class EmployeeCareerV2Screen extends StatefulWidget {
  const EmployeeCareerV2Screen({super.key, required this.employeeId, this.title});
  final String employeeId;
  final String? title;

  @override
  State<EmployeeCareerV2Screen> createState() => _EmployeeCareerV2ScreenState();
}

class _EmployeeCareerV2ScreenState extends State<EmployeeCareerV2Screen> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getEmployeeCareer(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được';
      }
    });
  }

  Map<String, dynamic> get _emp => Map<String, dynamic>.from((_data?['employee'] as Map?) ?? {});
  bool get _canEdit => _data?['canEdit'] == true;

  List<Map<String, dynamic>> get _events => [
        for (final e in (_data?['events'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(e),
      ];

  Future<void> _addRecord(String kind) async {
    final ok = await ecOpen(context, CareerRecordForm(employeeId: widget.employeeId, kind: kind));
    if (ok == true) _load();
  }

  Future<void> _move() async {
    final ok = await ecOpen(context, CareerMoveForm(employee: _emp));
    if (ok == true) _load();
  }

  Future<void> _edit(Map<String, dynamic> e) async {
    if (e['kind'] != 'award' && e['kind'] != 'discipline') return;
    final ok = await ecOpen(context, CareerRecordForm(employeeId: widget.employeeId, kind: '${e['kind']}', existing: e));
    if (ok == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final isMove = ['transfer', 'appointment', 'promotion'].contains(e['kind']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa "${e['title']}"?')),
        content: Text(tr(isMove
            ? 'Chỉ xóa dòng lịch sử. Phòng ban, chức vụ hiện tại trên hồ sơ giữ nguyên.'
            : 'Bản ghi sẽ bị xóa khỏi quá trình công tác.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.deleteCareerRecord('${e['recordId']}');
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(title: Text(tr(widget.title ?? 'Quá trình công tác'))),
      floatingActionButton: _canEdit && !wide && _data != null
          ? FloatingActionButton.extended(onPressed: _actionsSheet, icon: const Icon(Icons.add), label: Text(tr('Ghi nhận')))
          : null,
      body: _loading
          ? const SboxLoading(message: 'Đang tải quá trình công tác…')
          : _error != null
              ? SboxEmptyState(icon: Icons.cloud_off_rounded, title: 'Không tải được', message: _error)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 16, wide ? 24 : 12, 96),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _header(wide),
                            const SizedBox(height: 12),
                            _summary(wide),
                            const SizedBox(height: 14),
                            _filters(),
                            const SizedBox(height: 10),
                            _timeline(wide),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  void _actionsSheet() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(EcKind.of('transfer').icon, color: EcKind.of('transfer').color),
              title: Text(tr('Điều chuyển / bổ nhiệm / thăng chức')),
              onTap: () {
                Navigator.pop(ctx);
                _move();
              },
            ),
            ListTile(
              leading: Icon(EcKind.of('award').icon, color: EcKind.of('award').color),
              title: Text(tr('Khen thưởng')),
              onTap: () {
                Navigator.pop(ctx);
                _addRecord('award');
              },
            ),
            ListTile(
              leading: Icon(EcKind.of('discipline').icon, color: EcKind.of('discipline').color),
              title: Text(tr('Kỷ luật')),
              onTap: () {
                Navigator.pop(ctx);
                _addRecord('discipline');
              },
            ),
          ]),
        ),
      );

  String _tenure() {
    final j = DateTime.tryParse('${_emp['joinDate']}');
    if (j == null) return '—';
    final end = DateTime.tryParse('${_emp['resignationDate']}') ?? DateTime.now();
    var months = (end.year - j.year) * 12 + end.month - j.month;
    if (end.day < j.day) months--;
    if (months < 0) months = 0;
    final y = months ~/ 12;
    final m = months % 12;
    if (y == 0) return '$m tháng';
    return m == 0 ? '$y năm' : '$y năm $m tháng';
  }

  Widget _header(bool wide) {
    final e = _emp;
    final contractEnd = DateTime.tryParse('${e['contractEndDate']}');
    final expSoon = contractEnd != null && contractEnd.difference(DateTime.now()).inDays <= 30;
    final actions = _canEdit
        ? Wrap(spacing: 8, runSpacing: 8, children: [
            SboxButton(label: 'Điều chuyển / bổ nhiệm', icon: Icons.swap_horiz_rounded, onPressed: _move),
            SboxButton.secondary(label: 'Khen thưởng', icon: Icons.emoji_events_outlined, onPressed: () => _addRecord('award')),
            SboxButton.secondary(label: 'Kỷ luật', icon: Icons.gavel_rounded, onPressed: () => _addRecord('discipline')),
          ])
        : const SizedBox.shrink();
    final info = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DpAvatar(name: '${e['name'] ?? ''}', photo: e['photoUrl']?.toString(), size: 56),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('${e['name'] ?? ''}'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            tr([e['code'], e['position'], e['department'], e['branch']]
                .whereType<Object>()
                .map((x) => '$x')
                .where((x) => x.isNotEmpty)
                .join(' · ')),
            style: const TextStyle(color: SboxColors.slate600),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            SboxStatusChip(label: 'Vào làm ${ecDate(DateTime.tryParse('${e['joinDate']}'))}', icon: Icons.login_rounded),
            SboxStatusChip(label: 'Thâm niên ${_tenure()}', icon: Icons.workspace_premium_outlined, tone: SboxTone.brand),
            if (contractEnd != null)
              SboxStatusChip(
                label: 'HĐ hết hạn ${ecDate(contractEnd)}',
                icon: Icons.description_outlined,
                tone: expSoon ? SboxTone.warning : SboxTone.neutral,
              ),
            if (e['resignationDate'] != null)
              SboxStatusChip(label: 'Nghỉ việc ${ecDate(DateTime.tryParse('${e['resignationDate']}'))}', tone: SboxTone.danger),
          ]),
        ]),
      ),
    ]);
    return SboxCard(
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              SizedBox(width: 540, child: Align(alignment: Alignment.topRight, child: actions)),
            ])
          : info,
    );
  }

  Widget _summary(bool wide) {
    final s = Map<String, dynamic>.from((_data?['summary'] as Map?) ?? {});
    num n(String k) => (s[k] as num?) ?? 0;
    final cards = [
      SboxMetricCard(label: 'Điều chuyển / bổ nhiệm', value: '${n('moves')}', icon: Icons.swap_horiz_rounded),
      SboxMetricCard(
        label: 'Khen thưởng',
        value: '${n('awards')}',
        icon: Icons.emoji_events_rounded,
        tone: SboxTone.warning,
        delta: n('bonusTotal') > 0 ? '+${SboxFmt.money(n('bonusTotal'))}' : null,
        deltaUp: n('bonusTotal') > 0 ? true : null,
      ),
      SboxMetricCard(
        label: 'Kỷ luật',
        value: '${n('disciplines')}',
        icon: Icons.gavel_rounded,
        tone: SboxTone.danger,
        delta: n('penaltyTotal') > 0 ? '−${SboxFmt.money(n('penaltyTotal'))}' : null,
        deltaUp: n('penaltyTotal') > 0 ? false : null,
      ),
    ];
    if (!wide) {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 200, child: cards[i]),
        ),
      );
    }
    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  Widget _filters() {
    final counts = <String, int>{};
    for (final e in _events) {
      final g = EcKind.of('${e['kind']}').group;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final opts = {
      'all': 'Tất cả (${_events.length})',
      'work': 'Công tác (${counts['work'] ?? 0})',
      'reward': 'Khen thưởng (${counts['reward'] ?? 0})',
      'discipline': 'Kỷ luật (${counts['discipline'] ?? 0})',
      'paper': 'Hợp đồng & giấy tờ (${counts['paper'] ?? 0})',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in opts.entries)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tr(o.value)),
              selected: _filter == o.key,
              showCheckmark: false,
              selectedColor: SboxColors.brand50,
              onSelected: (_) => setState(() => _filter = o.key),
            ),
          ),
      ]),
    );
  }

  Widget _timeline(bool wide) {
    final list = _events.where((e) => _filter == 'all' || EcKind.of('${e['kind']}').group == _filter).toList();
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: SboxEmptyState(
          icon: Icons.timeline_rounded,
          title: 'Chưa có ghi nhận',
          message: _canEdit ? 'Bấm «Điều chuyển / bổ nhiệm», «Khen thưởng» hoặc «Kỷ luật» để ghi nhận.' : null,
        ),
      );
    }
    final children = <Widget>[];
    int? year;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      final d = DateTime.tryParse('${e['date']}')?.toLocal();
      if (d != null && d.year != year) {
        year = d.year;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 0, 6),
          child: Text('$year', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SboxColors.slate700)),
        ));
      }
      children.add(_eventRow(e, d, last: i == list.length - 1, wide: wide));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _eventRow(Map<String, dynamic> e, DateTime? d, {required bool last, required bool wide}) {
    final k = EcKind.of('${e['kind']}');
    final amount = (e['amount'] as num?) ?? 0;
    final negative = k.group == 'discipline';
    final atts = [for (final a in (e['attachments'] as List? ?? const [])) '$a'];
    final meta = <String>[
      if ('${e['decisionNumber'] ?? ''}'.isNotEmpty) 'Số QĐ ${e['decisionNumber']}',
      if ('${e['issuedBy'] ?? ''}'.isNotEmpty) 'Cấp QĐ: ${e['issuedBy']}',
      if (e['endDate'] != null) 'Hiệu lực đến ${ecDate(DateTime.tryParse('${e['endDate']}'))}',
      if (e['source'] == 'finance') 'Tài chính nhân sự',
      if (e['source'] == 'document') 'Hồ sơ giấy tờ',
    ];
    final pending = d != null && d.isAfter(DateTime.now()) && ['transfer', 'appointment', 'promotion'].contains(e['kind']);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate500)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Column(children: [
            const SizedBox(height: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: k.color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(k.icon, size: 17, color: k.color),
            ),
            if (!last) Expanded(child: Container(width: 2, color: SboxColors.slate200)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SboxCard(
              onTap: e['editable'] == true && (e['kind'] == 'award' || e['kind'] == 'discipline') ? () => _edit(e) : null,
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tr(k.label), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: k.color)),
                      if (pending) const SboxStatusChip(label: 'Chờ hiệu lực', tone: SboxTone.warning, dot: true),
                    ]),
                    const SizedBox(height: 2),
                    Text(tr('${e['title'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if ('${e['subtitle'] ?? ''}'.isNotEmpty)
                      Text(tr('${e['subtitle']}'), style: const TextStyle(color: SboxColors.slate600, fontSize: 13)),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tr(meta.join(' · ')), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                      ),
                    if ('${e['note'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tr('${e['note']}'), style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                      ),
                    if (atts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final a in atts)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(a.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded, size: 16),
                              label: Text(a.split('/').last, overflow: TextOverflow.ellipsis),
                              onPressed: () => launchUrl(Uri.parse(hrFinUrl(a)), mode: LaunchMode.externalApplication),
                            ),
                        ]),
                      ),
                  ]),
                ),
                if (amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 14, right: 6),
                    child: Text('${negative ? '−' : '+'}${SboxFmt.money(amount)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: negative ? SboxColors.dangerText : SboxColors.successText)),
                  ),
                if (e['editable'] == true)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: SboxColors.slate400),
                    onSelected: (v) => v == 'edit' ? _edit(e) : _delete(e),
                    itemBuilder: (_) => [
                      if (e['kind'] == 'award' || e['kind'] == 'discipline') PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                      PopupMenuItem(value: 'delete', child: Text(tr('Xóa'), style: const TextStyle(color: SboxColors.danger))),
                    ],
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
