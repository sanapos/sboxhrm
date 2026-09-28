import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_charts.dart';
import 'meal_menu_quick_editor.dart';
import 'meal_ticket_station_screen.dart';
import 'meal_ui.dart';

/// Màn hình căn tin: hôm nay bao nhiêu người đã ăn (theo buổi, so với đăng ký), ai đăng ký mà chưa ăn,
/// lượt chấm theo 15 phút, theo bộ phận, phiếu ăn mới nhất. Tự làm mới 15 giây/lần.
class MealCanteenLiveView extends StatefulWidget {
  const MealCanteenLiveView({super.key});

  @override
  State<MealCanteenLiveView> createState() => _MealCanteenLiveViewState();
}

class _MealCanteenLiveViewState extends State<MealCanteenLiveView> {
  final _api = ApiService();
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (MealUi.sameDay(_date, DateTime.now())) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await _api.getMealCanteenLive(date: _date);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _data = res['data'] as Map<String, dynamic>?;
        _error = null;
      } else if (!silent) {
        _error = res['message']?.toString() ?? 'Không tải được số liệu căn tin';
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d != null) {
      setState(() => _date = d);
      _load();
    }
  }

  List<Map<String, dynamic>> _list(String key) => [
        for (final x in (_data?[key] as List? ?? const []))
          if (x is Map<String, dynamic>) x,
      ];

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)));
    }
    final t = _data?['totals'] as Map<String, dynamic>? ?? const {};
    final sessions = _list('sessions');
    final currentId = _data?['currentSessionId']?.toString();
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final pad = c.maxWidth < 600 ? 12.0 : 20.0;
        Widget two(Widget a, Widget b) => wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: 16),
                Expanded(child: b),
              ])
            : Column(children: [a, const SizedBox(height: 16), b]);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
          children: [
            _toolbar(),
            const SizedBox(height: 14),
            MealUi.statGrid([
              MealUi.stat('Suất đã phục vụ', '${MealUi.n(t['served']).toInt()}',
                  icon: Icons.restaurant_rounded, note: '${MealUi.n(t['people']).toInt()} người'),
              MealUi.stat('Đã đăng ký', '${MealUi.n(t['registered']).toInt()}',
                  icon: Icons.event_available_rounded, color: SboxColors.violet),
              MealUi.stat('Ăn không đăng ký', '${MealUi.n(t['walkIn']).toInt()}',
                  icon: Icons.directions_walk_rounded, color: SboxColors.warning),
              MealUi.stat('Đăng ký chưa ăn', '${MealUi.n(t['noShow']).toInt()}',
                  icon: Icons.person_off_rounded, color: SboxColors.danger),
              MealUi.stat('Tiền ăn', MealUi.money(t['amount']),
                  icon: Icons.payments_rounded, color: SboxColors.success),
              MealUi.stat('Phiếu chưa in', '${MealUi.n(t['unprinted']).toInt()}',
                  icon: Icons.print_disabled_rounded,
                  color: MealUi.n(t['unprinted']) > 0 ? SboxColors.warning : SboxColors.slate400),
            ], minWidth: 170),
            const SizedBox(height: 16),
            MealUi.sectionTitle('Theo buổi ăn', icon: Icons.schedule_rounded),
            LayoutBuilder(builder: (context, cc) {
              final cols = cc.maxWidth >= 1100 ? 3 : cc.maxWidth >= 700 ? 2 : 1;
              final w = (cc.maxWidth - (cols - 1) * 14) / cols;
              return Wrap(spacing: 14, runSpacing: 14, children: [
                for (final s in sessions)
                  SizedBox(width: w, child: _sessionCard(s, s['id']?.toString() == currentId)),
              ]);
            }),
            const SizedBox(height: 16),
            two(_quarterCard(), _departmentCard()),
            const SizedBox(height: 16),
            _recentCard(),
          ],
        );
      }),
    );
  }

  Widget _toolbar() {
    final isToday = MealUi.sameDay(_date, DateTime.now());
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: Text(MealUi.dateLong(_date)),
      ),
      if (isToday)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: SboxColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(tr('Trực tiếp · tự làm mới 15 giây'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
        ]),
      FilledButton.icon(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MealTicketStationScreen()))
            .then((_) => _load(silent: true)),
        icon: const Icon(Icons.print_rounded, size: 18),
        label: Text(tr('Mở trạm in phiếu ăn')),
      ),
    ]);
  }

  Widget _sessionCard(Map<String, dynamic> s, bool current) {
    final served = MealUi.n(s['served']).toInt();
    final registered = MealUi.n(s['registered']).toInt();
    final target = registered > 0 ? registered : served;
    final progress = target == 0 ? 0.0 : (served / target).clamp(0.0, 1.0);
    final dishes = [
      for (final d in (s['dishes'] as List? ?? const []))
        if (d is Map) d['dishName']?.toString() ?? '',
    ];
    final noShow = [for (final n in (s['noShowNames'] as List? ?? const [])) n.toString()];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: current ? SboxColors.success : SboxColors.slate200, width: current ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(MealUi.sessionIcon(s['name']?.toString() ?? ''), color: SboxColors.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${s['name']}  ·  ${s['startTime']}–${s['endTime']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (current) MealUi.phaseChip('open'),
          IconButton(
            tooltip: tr('Nhập thực đơn'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_note_rounded, color: SboxColors.brand600),
            onPressed: () async {
              final ok = await showMealMenuQuickEditor(context,
                  date: _date, sessionId: s['id'].toString(), sessionName: s['name'].toString());
              if (ok) _load(silent: true);
            },
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$served',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1, color: SboxColors.slate900)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(tr(registered > 0 ? '/ $registered đăng ký' : 'suất'),
                style: const TextStyle(color: SboxColors.slate500)),
          ),
          const Spacer(),
          Text(MealUi.money(s['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: SboxColors.slate100,
            color: SboxColors.success,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _pill('Ăn không đăng ký: ${MealUi.n(s['walkIn']).toInt()}', SboxColors.warning),
          _pill('Đăng ký chưa ăn: ${MealUi.n(s['noShow']).toInt()}', SboxColors.danger),
        ]),
        if (dishes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(dishes.join(' · '),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
        ] else ...[
          const SizedBox(height: 10),
          Text(tr('Chưa có thực đơn'), style: const TextStyle(fontSize: 12.5, color: SboxColors.warningText)),
        ],
        if (noShow.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(tr('Danh sách đăng ký chưa ăn (${noShow.length})'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final n in noShow) Chip(label: Text(n), visualDensity: VisualDensity.compact),
                  ]),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
        child: Text(tr(text), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _quarterCard() {
    final q = _list('byQuarter');
    return MealUi.card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MealUi.sectionTitle('Lượt chấm theo 15 phút', icon: Icons.bar_chart_rounded),
        if (q.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr('Chưa có lượt chấm'), style: const TextStyle(color: SboxColors.slate400))),
          )
        else
          SboxBarChart(
            labels: [for (final x in q) x['time'].toString()],
            series: [
              SboxSeries(
                name: 'Lượt chấm',
                values: [for (final x in q) MealUi.n(x['count']).toDouble()],
                color: SboxColors.brand500,
              ),
            ],
            height: 200,
            showLegend: false,
            valueFormat: (v) => SboxFmt.number(v),
            axisFormat: (v) => SboxFmt.number(v),
          ),
      ]),
    );
  }

  Widget _departmentCard() {
    final d = _list('byDepartment');
    final max = d.isEmpty ? 1 : d.map((x) => MealUi.n(x['count'])).reduce((a, b) => a > b ? a : b);
    return MealUi.card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MealUi.sectionTitle('Theo bộ phận', icon: Icons.apartment_rounded),
        if (d.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr('Chưa có dữ liệu'), style: const TextStyle(color: SboxColors.slate400))),
          )
        else
          for (final x in d.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: Text(x['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : MealUi.n(x['count']) / max,
                      minHeight: 10,
                      backgroundColor: SboxColors.slate100,
                      color: SboxColors.brand500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${MealUi.n(x['count']).toInt()}',
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _recentCard() {
    final r = _list('recent');
    return MealUi.card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MealUi.sectionTitle('Phiếu ăn mới nhất', icon: Icons.receipt_long_rounded),
        if (r.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr('Chưa có ai chấm cơm'), style: const TextStyle(color: SboxColors.slate400))),
          )
        else
          for (final x in r)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: SboxColors.brand50,
                child: Text('${x['ticketNo']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SboxColors.brand700)),
              ),
              title: Text(x['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                x['session'],
                if ((x['department']?.toString() ?? '').isNotEmpty) x['department'],
                x['source'],
              ].join(' · ')),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Text(MealUi.time(DateTime.tryParse(x['time'].toString()) ?? DateTime.now()),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Icon(x['printed'] == true ? Icons.print_rounded : Icons.print_disabled_rounded,
                    size: 14, color: x['printed'] == true ? SboxColors.success : SboxColors.warning),
              ]),
            ),
      ]),
    );
  }
}
