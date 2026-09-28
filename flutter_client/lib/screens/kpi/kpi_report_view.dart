import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';

/// Tab «Báo cáo» KPI: tỷ lệ hoàn thành, phân bố mức đạt, theo phòng ban / tiêu chí,
/// nhân viên xuất sắc / cần cải thiện, lương KPI và so sánh với kỳ trước.
class KpiReportView extends StatefulWidget {
  const KpiReportView({super.key, this.periodId});

  final String? periodId;

  @override
  State<KpiReportView> createState() => _KpiReportViewState();
}

class _KpiReportViewState extends State<KpiReportView> {
  final _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KpiReportView old) {
    super.didUpdateWidget(old);
    if (old.periodId != widget.periodId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getKpiReport(periodId: widget.periodId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo KPI';
      }
    });
  }

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _list(String key) {
    final raw = _data?[key];
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Map<String, dynamic> _map(String key) =>
      _data?[key] is Map ? Map<String, dynamic>.from(_data![key] as Map) : {};

  Color _pctColor(double pct) => pct >= 100
      ? SboxColors.successText
      : pct >= 80
          ? SboxColors.warningText
          : SboxColors.dangerText;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.dangerText)));
    }
    if (_data?['hasData'] != true) {
      return Center(
        child: Text(tr('Kỳ này chưa có chỉ tiêu / kết quả KPI'),
            style: const TextStyle(color: SboxColors.slate500)),
      );
    }
    final sum = _map('summary');
    final prev = _map('previousSummary');
    final hasPrev = prev.isNotEmpty;
    final prevName = (_map('previousPeriod')['name'] ?? '').toString();
    final distribution = _list('distribution');
    final byDept = _list('byDepartment');
    final byCriteria = _list('byCriteria');
    final employees = _n(sum['employees']);
    final achieved = _n(sum['achieved']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          SboxInsightPanel(
            kpis: [
              SboxKpi(
                label: 'Hoàn thành trung bình',
                value: SboxFmt.pct(_n(sum['avgCompletion'])),
                icon: Icons.track_changes_rounded,
                tone: SboxTone.brand,
                current: _n(sum['avgCompletion']),
                previous: hasPrev ? _n(prev['avgCompletion']) : null,
                compareLabel: hasPrev ? prevName : null,
              ),
              SboxKpi(
                label: 'Đạt chỉ tiêu (≥100%)',
                value: '${achieved.toInt()}/${employees.toInt()}',
                icon: Icons.emoji_events_outlined,
                tone: SboxTone.success,
                note: employees > 0 ? 'Tỷ lệ ${SboxFmt.pct(achieved / employees * 100)}' : null,
              ),
              SboxKpi(
                label: 'Tổng lương KPI',
                value: SboxFmt.money(_n(sum['totalPay'])),
                icon: Icons.payments_outlined,
                tone: SboxTone.violet,
                current: _n(sum['totalPay']),
                previous: hasPrev ? _n(prev['totalPay']) : null,
                compareLabel: hasPrev ? prevName : null,
                higherIsBetter: false,
              ),
              SboxKpi(
                label: 'Lương đã duyệt',
                value: '${_n(_data?['approvedCount']).toInt()}/${employees.toInt()}',
                icon: Icons.verified_outlined,
                tone: SboxTone.warning,
              ),
            ],
            charts: [
              SboxChartCard(
                title: 'Phân bố mức hoàn thành',
                subtitle: 'Số nhân viên theo khoảng % đạt chỉ tiêu',
                child: SboxBarChart(
                  labels: [for (final d in distribution) d['label'].toString()],
                  valueFormat: (v) => '${SboxFmt.number(v)} NV',
                  axisFormat: (v) => SboxFmt.number(v),
                  series: [
                    SboxSeries(
                      name: 'Nhân viên',
                      values: [for (final d in distribution) _n(d['count'])],
                      color: SboxColors.brand600,
                    ),
                  ],
                ),
              ),
              if (byDept.length > 1)
                SboxChartCard(
                  title: 'Hoàn thành theo phòng ban',
                  child: SboxBarChart(
                    labels: [for (final d in byDept) d['department'].toString()],
                    valueFormat: (v) => SboxFmt.pct(v),
                    axisFormat: (v) => SboxFmt.number(v),
                    series: [
                      SboxSeries(
                        name: '% hoàn thành TB',
                        values: [for (final d in byDept) _n(d['avgCompletion'])],
                        color: SboxColors.success,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (byCriteria.isNotEmpty)
            _section(
              'Theo tiêu chí',
              Column(
                children: [
                  for (final c in byCriteria)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(c['criteria'].toString()),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(tr('Thực tế ${SboxFmt.number(_n(c['actual']))} / '
                          'chỉ tiêu ${SboxFmt.number(_n(c['target']))}')),
                      trailing: Text(SboxFmt.pct(_n(c['completionPct'])),
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: _pctColor(_n(c['completionPct'])))),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _section('Phòng ban', Column(children: [for (final d in byDept) _deptRow(d)])),
          const SizedBox(height: 12),
          _section('Nhân viên xuất sắc', Column(children: [for (final r in _list('top')) _empRow(r)])),
          const SizedBox(height: 12),
          _section(
            'Cần cải thiện (dưới 100%)',
            _list('needImprovement').isEmpty
                ? Text(tr('Tất cả nhân viên đã đạt chỉ tiêu'),
                    style: const TextStyle(color: SboxColors.successText))
                : Column(children: [for (final r in _list('needImprovement')) _empRow(r)]),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: SboxColors.slate200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  Widget _deptRow(Map<String, dynamic> d) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(tr(d['department'].toString()), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(tr('${_n(d['achieved']).toInt()}/${_n(d['employees']).toInt()} NV đạt · '
            'lương KPI ${SboxFmt.money(_n(d['totalPay']))}')),
        trailing: Text(SboxFmt.pct(_n(d['avgCompletion'])),
            style: TextStyle(fontWeight: FontWeight.w700, color: _pctColor(_n(d['avgCompletion'])))),
      );

  Widget _empRow(Map<String, dynamic> r) {
    final pct = _n(r['completionPct']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${r['employeeName'] ?? ''} (${r['employeeCode'] ?? ''})',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr('${(r['department'] ?? '').toString().isEmpty ? '' : '${r['department']} · '}'
          'Lương KPI ${SboxFmt.money(_n(r['pay']))}${r['approved'] == true ? ' · đã duyệt' : ''}')),
      trailing: SizedBox(
        width: 90,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(SboxFmt.pct(pct), style: TextStyle(fontWeight: FontWeight.w700, color: _pctColor(pct))),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (pct / 150).clamp(0, 1).toDouble(),
              minHeight: 5,
              color: _pctColor(pct),
              backgroundColor: SboxColors.slate200,
            ),
          ],
        ),
      ),
    );
  }
}
