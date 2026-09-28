import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';

/// Tab «Báo cáo» của màn Sản lượng: tổng hợp, so với kỳ trước, theo ngày,
/// theo sản phẩm / nhóm, xếp hạng nhân viên; tính lại đơn giá tháng.
class ProductionReportView extends StatefulWidget {
  const ProductionReportView({
    super.key,
    required this.fromDate,
    required this.toDate,
    this.employeeId,
    this.productGroupId,
    this.canEdit = false,
  });

  final DateTime fromDate;
  final DateTime toDate;
  final String? employeeId;
  final String? productGroupId;
  final bool canEdit;

  @override
  State<ProductionReportView> createState() => _ProductionReportViewState();
}

class _ProductionReportViewState extends State<ProductionReportView> {
  final _api = ApiService();
  bool _loading = true;
  bool _repricing = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductionReportView old) {
    super.didUpdateWidget(old);
    if (old.fromDate != widget.fromDate ||
        old.toDate != widget.toDate ||
        old.employeeId != widget.employeeId ||
        old.productGroupId != widget.productGroupId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getProductionReport(
      fromDate: widget.fromDate,
      toDate: widget.toDate,
      employeeId: widget.employeeId,
      productGroupId: widget.productGroupId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _data = null;
        _error = res['message']?.toString() ?? 'Không tải được báo cáo sản lượng';
      }
    });
  }

  Future<void> _reprice() async {
    final month = DateTime(widget.toDate.year, widget.toDate.month);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tính lại đơn giá tháng ${month.month}/${month.year}')),
        content: Text(tr(
            'Tính lại đơn giá lũy tiến và thành tiền của toàn bộ sản lượng trong tháng theo bảng giá hiện tại '
            '(dùng sau khi sửa bậc giá). Nhân viên đã chốt lương tháng này được giữ nguyên.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tính lại'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _repricing = true);
    final res = await _api.repriceProductionMonth(year: month.year, month: month.month);
    if (!mounted) return;
    setState(() => _repricing = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final d = res['data'] as Map;
      NotificationOverlayManager().showSuccess(
        title: 'Đã tính lại đơn giá',
        message: tr('Thành tiền tháng: ${SboxFmt.money(_n(d['amountBefore']))} → '
            '${SboxFmt.money(_n(d['amountAfter']))}'
            '${_n(d['lockedSkipped']) > 0 ? ' · ${_n(d['lockedSkipped']).toInt()} dòng đã chốt lương giữ nguyên' : ''}'),
        duration: const Duration(seconds: 6),
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không tính lại được',
        message: res['message']?.toString() ?? 'Lỗi tính lại đơn giá',
      );
    }
  }

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _list(String key) {
    final raw = _data?[key];
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  String? _changeNote(dynamic pct) {
    if (pct == null) return 'Kỳ trước chưa có dữ liệu';
    final v = _n(pct);
    return '${v >= 0 ? '▲' : '▼'} ${v.abs().toStringAsFixed(1)}% so với kỳ trước';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.dangerText)));
    }
    final totals = Map<String, dynamic>.from((_data?['totals'] as Map?) ?? {});
    final daily = _list('daily');
    final byProduct = _list('byProduct');
    final byGroup = _list('byGroup');
    final byEmployee = _list('byEmployee');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          if (widget.canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _repricing ? null : _reprice,
                icon: _repricing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.price_change_outlined, size: 18),
                label: Text(tr('Tính lại đơn giá tháng ${widget.toDate.month}/${widget.toDate.year}')),
              ),
            ),
          const SizedBox(height: 8),
          SboxInsightPanel(
            kpis: [
              SboxKpi(
                label: 'Lương sản phẩm',
                value: SboxFmt.money(_n(totals['amount'])),
                icon: Icons.payments_outlined,
                tone: SboxTone.success,
                note: _changeNote(totals['amountChangePct']),
              ),
              SboxKpi(
                label: 'Sản lượng',
                value: SboxFmt.number(_n(totals['quantity'])),
                icon: Icons.inventory_2_outlined,
                tone: SboxTone.brand,
                note: _changeNote(totals['quantityChangePct']),
              ),
              SboxKpi(
                label: 'Nhân viên',
                value: SboxFmt.number(_n(totals['employees'])),
                icon: Icons.groups_outlined,
                tone: SboxTone.violet,
                note: 'TB ${SboxFmt.money(_n(totals['amountPerEmployee']))} / NV',
              ),
              SboxKpi(
                label: 'Ngày có sản lượng',
                value: SboxFmt.number(_n(totals['workDays'])),
                icon: Icons.calendar_month_outlined,
                tone: SboxTone.warning,
                note: 'TB ${SboxFmt.money(_n(totals['amountPerDay']))} / ngày',
              ),
            ],
            charts: [
              if (daily.length > 1)
                SboxChartCard(
                  title: 'Lương sản phẩm theo ngày',
                  subtitle: 'Thành tiền sản lượng mỗi ngày',
                  child: SboxBarChart(
                    labels: [
                      for (final d in daily)
                        d['date'].toString().substring(5).split('-').reversed.join('/'),
                    ],
                    series: [
                      SboxSeries(
                        name: 'Thành tiền',
                        values: [for (final d in daily) _n(d['amount'])],
                        color: SboxColors.success,
                      ),
                    ],
                  ),
                ),
              if (byGroup.isNotEmpty)
                SboxChartCard(
                  title: 'Cơ cấu theo nhóm sản phẩm',
                  child: SboxDonutChart(
                    valueFormat: (v) => SboxFmt.money(v),
                    slices: [
                      for (final g in byGroup) SboxSlice(g['name']?.toString() ?? '—', _n(g['amount'])),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            'Xếp hạng nhân viên',
            byEmployee.isEmpty
                ? _empty()
                : Column(
                    children: [
                      for (var i = 0; i < byEmployee.length; i++) _employeeRow(i + 1, byEmployee[i]),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _section(
            'Theo sản phẩm',
            byProduct.isEmpty
                ? _empty()
                : Column(children: [for (final p in byProduct) _productRow(p)]),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr('Chưa có sản lượng trong khoảng này'),
            style: const TextStyle(color: SboxColors.slate500)),
      );

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

  Widget _employeeRow(int rank, Map<String, dynamic> e) {
    final medal = rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(width: 28, child: Center(child: Text(medal))),
      title: Text('${e['employeeName'] ?? ''} (${e['employeeCode'] ?? ''})',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr(
          '${(e['department'] ?? '').toString().isEmpty ? '' : '${e['department']} · '}'
          '${SboxFmt.number(_n(e['quantity']))} SP · ${_n(e['workDays']).toInt()} ngày · '
          'TB ${SboxFmt.money(_n(e['amountPerDay']))}/ngày')),
      trailing: Text(SboxFmt.money(_n(e['amount'])),
          style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.successText)),
    );
  }

  Widget _productRow(Map<String, dynamic> p) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${p['name'] ?? ''}${(p['code'] ?? '').toString().isEmpty ? '' : ' · ${p['code']}'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(tr(
            '${p['groupName'] ?? ''} · ${SboxFmt.number(_n(p['quantity']))} ${p['unit'] ?? 'SP'} · '
            'giá TB ${SboxFmt.money(_n(p['avgUnitPrice']))} · ${_n(p['employees']).toInt()} NV')),
        trailing: Text(SboxFmt.money(_n(p['amount'])),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
