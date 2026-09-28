import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_charts.dart';
import '../feedback_detail_screen.dart';
import 'feedback_ui.dart';

/// Báo cáo kiến nghị / khiếu nại: tổng quan, tỷ lệ đúng hạn, thời gian phản hồi / giải quyết,
/// mức hài lòng, xu hướng theo tháng, chủ đề nóng, bộ phận, hiệu quả người xử lý, phiếu tồn lâu nhất.
class FeedbackReportView extends StatefulWidget {
  const FeedbackReportView({super.key});

  @override
  State<FeedbackReportView> createState() => _FeedbackReportViewState();
}

class _FeedbackReportViewState extends State<FeedbackReportView> {
  final _api = ApiService();
  int _months = 6;
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - (_months - 1), 1);
    final res = await _api.getFeedbackStats(fromDate: from, toDate: now);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _d = res['data'] as Map<String, dynamic>?;
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  List<Map<String, dynamic>> _list(String k) => [
        for (final x in (_d?[k] as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  num _num(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  String _hours(dynamic v) {
    if (v == null) return '—';
    final h = _num(v).toDouble();
    return h >= 48 ? '${(h / 24).toStringAsFixed(1)} ngày' : '${h.toStringAsFixed(1)} giờ';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _d == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _d == null) {
      return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)));
    }
    final t = _d?['totals'] as Map<String, dynamic>? ?? const {};
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 980;
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
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [1, 3, 6, 12])
                ChoiceChip(
                  label: Text(tr(m == 1 ? 'Tháng này' : '$m tháng')),
                  selected: _months == m,
                  onSelected: (_) {
                    setState(() => _months = m);
                    _load();
                  },
                ),
            ]),
            const SizedBox(height: 14),
            _statGrid([
              _stat('Tổng phiếu', '${_num(t['total'])}', Icons.all_inbox_rounded, SboxColors.brand600,
                  note: '${_num(t['complaints'])} khiếu nại · ${_num(t['anonymous'])} ẩn danh'),
              _stat('Đang mở', '${_num(t['open'])}', Icons.pending_actions_rounded, SboxColors.warning,
                  note: '${_num(t['pending'])} chờ tiếp nhận'),
              _stat('Quá hạn', '${_num(t['overdue'])}', Icons.alarm_rounded,
                  _num(t['overdue']) > 0 ? SboxColors.danger : SboxColors.success),
              _stat('Đúng hạn', t['onTimePct'] == null ? '—' : '${t['onTimePct']}%', Icons.verified_rounded,
                  SboxColors.success, note: 'trên số phiếu đã giải quyết'),
              _stat('Phản hồi đầu TB', _hours(t['avgFirstResponseHours']), Icons.reply_rounded, SboxColors.violet),
              _stat('Giải quyết TB', _hours(t['avgResolveHours']), Icons.timelapse_rounded, SboxColors.brand500),
              _stat('Hài lòng', t['avgRating'] == null ? '—' : '${t['avgRating']}/5', Icons.star_rounded,
                  const Color(0xFFF5A524), note: '${_num(t['rated'])} lượt đánh giá · ${_num(t['reopened'])} mở lại'),
            ]),
            const SizedBox(height: 16),
            _card('Xu hướng theo tháng', Icons.show_chart_rounded, _trend()),
            const SizedBox(height: 16),
            two(
              _card('Chủ đề được phản ánh nhiều', Icons.local_fire_department_rounded,
                  _bars(_list('byTopic'), 'name', extra: (x) => '${_num(x['complaints'])} khiếu nại')),
              _card('Theo bộ phận người gửi', Icons.apartment_rounded,
                  _bars(_list('byDepartment'), 'name', extra: (x) => '${_num(x['complaints'])} khiếu nại')),
            ),
            const SizedBox(height: 16),
            two(
              _card('Theo loại phiếu', Icons.category_rounded, _bars(_list('byCategory'), 'name',
                  extra: (x) => '${_num(x['open'])} đang mở')),
              _card('Theo mức độ', Icons.flag_rounded, _bars(_list('byPriority'), 'name',
                  extra: (x) => '${_num(x['overdue'])} quá hạn')),
            ),
            const SizedBox(height: 16),
            _card('Hiệu quả người xử lý', Icons.support_agent_rounded, _handlers()),
            const SizedBox(height: 16),
            _card('Phiếu tồn cần ưu tiên', Icons.priority_high_rounded, _oldest()),
          ],
        );
      }),
    );
  }

  Widget _statGrid(List<Widget> items) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 190).floor().clamp(2, 7);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
      });

  Widget _stat(String label, String value, IconData icon, Color color, {String? note}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
          if (note != null)
            Text(tr(note), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: SboxColors.slate400)),
        ]),
      );

  Widget _card(String title, IconData icon, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 18, color: SboxColors.brand600),
            const SizedBox(width: 8),
            Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _emptyNote() => Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(tr('Chưa có dữ liệu'), style: const TextStyle(color: SboxColors.slate400))),
      );

  Widget _trend() {
    final m = _list('byMonth');
    if (m.isEmpty) return _emptyNote();
    return SboxBarChart(
      labels: [for (final x in m) x['month'].toString()],
      series: [
        SboxSeries(name: 'Tiếp nhận', values: [for (final x in m) _num(x['received']).toDouble()], color: SboxColors.brand500),
        SboxSeries(name: 'Đã giải quyết', values: [for (final x in m) _num(x['resolved']).toDouble()], color: SboxColors.success),
        SboxSeries(name: 'Khiếu nại', values: [for (final x in m) _num(x['complaints']).toDouble()], color: SboxColors.danger),
      ],
      height: 220,
      valueFormat: (v) => SboxFmt.number(v),
      axisFormat: (v) => SboxFmt.number(v),
    );
  }

  Widget _bars(List<Map<String, dynamic>> rows, String key, {String Function(Map<String, dynamic>)? extra}) {
    final shown = rows.where((x) => _num(x['count']) > 0).take(8).toList();
    if (shown.isEmpty) return _emptyNote();
    final max = shown.map((x) => _num(x['count'])).reduce((a, b) => a > b ? a : b);
    return Column(children: [
      for (final x in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(tr(x[key].toString()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              if (extra != null)
                Text(tr(extra(x)), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate400)),
              const SizedBox(width: 10),
              Text('${_num(x['count'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : _num(x['count']) / max,
                minHeight: 8,
                backgroundColor: SboxColors.slate100,
                color: SboxColors.brand500,
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _handlers() {
    final rows = _list('handlers');
    if (rows.isEmpty) return _emptyNote();
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate600);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(SboxColors.slate50),
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('NGƯỜI XỬ LÝ', style: head)),
          DataColumn(numeric: true, label: Text('PHIẾU', style: head)),
          DataColumn(numeric: true, label: Text('ĐANG MỞ', style: head)),
          DataColumn(numeric: true, label: Text('QUÁ HẠN', style: head)),
          DataColumn(numeric: true, label: Text('ĐÚNG HẠN', style: head)),
          DataColumn(numeric: true, label: Text('TG GIẢI QUYẾT', style: head)),
          DataColumn(label: Text('HÀI LÒNG', style: head)),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(r['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('${_num(r['total'])}')),
              DataCell(Text('${_num(r['open'])}')),
              DataCell(Text('${_num(r['overdue'])}',
                  style: TextStyle(color: _num(r['overdue']) > 0 ? SboxColors.danger : null, fontWeight: FontWeight.w700))),
              DataCell(Text(r['onTimePct'] == null ? '—' : '${r['onTimePct']}%')),
              DataCell(Text(_hours(r['avgResolveHours']))),
              DataCell(r['avgRating'] == null
                  ? const Text('—')
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      FeedbackUi.stars(_num(r['avgRating']).round(), size: 14),
                      const SizedBox(width: 4),
                      Text('${r['avgRating']}'),
                    ])),
            ]),
        ],
      ),
    );
  }

  Widget _oldest() {
    final rows = _list('oldestOpen');
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(tr('Không còn phiếu tồn 🎉'), style: const TextStyle(color: SboxColors.success)),
        ),
      );
    }
    return Column(children: [
      for (final r in rows)
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => FeedbackDetailScreen(feedbackId: r['id'].toString(), isMine: false)))
              .then((_) => _load()),
          leading: CircleAvatar(
            backgroundColor: (r['overdue'] == true ? SboxColors.danger : SboxColors.warning).withValues(alpha: 0.12),
            child: Text('${_num(r['ageDays'])}d',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: r['overdue'] == true ? SboxColors.danger : SboxColors.warning)),
          ),
          title: Text(r['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([
            r['code'],
            r['statusName'],
            r['priorityName'],
            r['assignee'] ?? 'Chưa giao',
          ].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · ')),
          trailing: r['overdue'] == true ? FeedbackUi.pill('Quá hạn', SboxColors.danger) : null,
        ),
    ]);
  }
}
