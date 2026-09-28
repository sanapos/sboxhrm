import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Báo cáo vận chuyển: theo hãng, giao thất bại, hoàn hàng, hủy vận đơn, đối soát COD, lãi/lỗ ship.
class PosShippingReportScreen extends StatefulWidget {
  const PosShippingReportScreen({super.key});

  @override
  State<PosShippingReportScreen> createState() => _PosShippingReportScreenState();
}

class _PosShippingReportScreenState extends State<PosShippingReportScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _dt = DateFormat('dd/MM HH:mm');
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time = const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _carrier;
  int _tab = 0;
  final Set<String> _codPicked = {};

  static const _tabs = ['Theo hãng', 'Giao thất bại', 'Hoàn hàng', 'Hủy vận đơn', 'Đối soát COD'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosShippingReport(from: _time.from, to: _time.to, carrier: _carrier);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _codPicked.clear();
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không tải được báo cáo',
        message: res['message']?.toString() ?? 'Lỗi',
      );
    }
  }

  List<Map<String, dynamic>> _maps(dynamic raw) =>
      raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

  num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  String _t(dynamic iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return _dt.format((d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute)).toLocal());
  }

  Future<void> _confirmReturn(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận đã nhận hàng hoàn?')),
        content: Text(tr('Đơn ${r['orderNo']} — hàng sẽ được nhập lại kho và đơn bán bị hủy (trừ doanh thu, công nợ, điểm).')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đã nhận hàng'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.confirmPosShipmentReturn('${r['orderId']}');
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã nhận hàng hoàn', message: '${r['orderNo']}');
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không xác nhận được', message: res['message']?.toString() ?? 'Lỗi');
    }
  }

  Future<void> _settleCod() async {
    if (_codPicked.isEmpty) return;
    final res = await _api.settlePosShipmentCod(_codPicked.toList());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã đánh dấu đối soát', message: '${_codPicked.length} đơn');
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không cập nhật được', message: res['message']?.toString() ?? 'Lỗi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _data?['total'] is Map ? Map<String, dynamic>.from(_data!['total'] as Map) : <String, dynamic>{};
    final byCarrier = _maps(_data?['byCarrier']);
    return PosReportMobileScaffold(
      title: 'Báo cáo vận chuyển',
      time: _time,
      pngKey: _pngKey,
      onTimeChanged: (t) {
        setState(() => _time = t);
        _load();
      },
      onExportExcel: () => unawaited(PosReportExport.serverExcel(
        context: context,
        filePrefix: 'POS_VanChuyen',
        successMessage: 'Đã xuất Excel báo cáo vận chuyển',
        fetch: () => _api.exportPosShippingReportExcel(from: _time.from, to: _time.to, carrier: _carrier),
      )),
      // Khung báo cáo trên màn rộng không bọc Material — chip / ô chọn cần Material cha.
      body: Material(
        color: Colors.transparent,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _carrierFilter(byCarrier),
                const SizedBox(height: 8),
                _insight(total, byCarrier),
                _summary(total),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(tr('${_tabs[i]}${_tabCount(i)}')),
                          selected: _tab == i,
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                ..._tabBody(byCarrier),
              ],
            ),
      ),
    );
  }

  String _tabCount(int i) {
    final key = ['byCarrier', 'failed', 'returns', 'cancelled', 'cod'][i];
    final n = _maps(_data?[key]).length;
    return n > 0 ? ' ($n)' : '';
  }

  Widget _carrierFilter(List<Map<String, dynamic>> byCarrier) {
    if (byCarrier.isEmpty && _carrier == null) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      ChoiceChip(
        label: Text(tr('Tất cả hãng')),
        selected: _carrier == null,
        onSelected: (_) {
          setState(() => _carrier = null);
          _load();
        },
      ),
      for (final c in byCarrier)
        ChoiceChip(
          label: Text('${c['carrierName'] ?? c['carrierCode']}'),
          selected: _carrier == '${c['carrierCode']}',
          onSelected: (_) {
            setState(() => _carrier = '${c['carrierCode']}');
            _load();
          },
        ),
    ]);
  }

  Widget _insight(Map<String, dynamic> t, List<Map<String, dynamic>> byCarrier) {
    double n(dynamic v) => _n(v).toDouble();
    final profit = n(t['shipProfit']);
    String name(Map<String, dynamic> c) => '${c['carrierName'] ?? c['carrierCode'] ?? '—'}';
    final other = (n(t['shipments']) - n(t['delivered']) - n(t['failedOrders']) - n(t['returning']) - n(t['returned']) - n(t['cancelled']))
        .clamp(0, double.infinity)
        .toDouble();
    return SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Vận đơn', value: SboxFmt.number(n(t['shipments'])), icon: Icons.local_shipping_outlined, note: _time.displayLabel),
        SboxKpi(label: 'Giao thành công', value: SboxFmt.pct(n(t['successRate'])), icon: Icons.task_alt_rounded, tone: SboxTone.success,
            note: '${SboxFmt.number(n(t['delivered']))} đơn đã giao'),
        SboxKpi(label: 'Thất bại / hoàn', value: SboxFmt.number(n(t['failedOrders']) + n(t['returning']) + n(t['returned'])),
            icon: Icons.assignment_return_outlined, tone: SboxTone.danger, note: 'Cần gọi khách / nhận hàng hoàn'),
        SboxKpi(label: 'Lãi / lỗ phí ship', value: SboxFmt.money(profit), icon: Icons.savings_outlined,
            tone: profit < 0 ? SboxTone.danger : SboxTone.brand, note: 'Phí thu khách − cước hãng'),
        SboxKpi(label: 'COD chưa đối soát', value: SboxFmt.money(n(t['codPending'])), icon: Icons.account_balance_wallet_outlined, tone: SboxTone.warning),
      ],
      charts: [
        SboxChartCard(
          title: 'Kết quả giao theo hãng',
          child: SboxBarChart(
            stacked: true,
            valueFormat: (v) => '${SboxFmt.number(v)} đơn',
            axisFormat: (v) => SboxFmt.number(v),
            labels: [for (final c in byCarrier) name(c)],
            series: [
              SboxSeries(name: 'Đã giao', values: [for (final c in byCarrier) n(c['delivered'])], color: SboxColors.success),
              SboxSeries(name: 'Thất bại', values: [for (final c in byCarrier) n(c['failedOrders'])], color: SboxColors.warning),
              SboxSeries(name: 'Hoàn', values: [for (final c in byCarrier) n(c['returning']) + n(c['returned'])], color: SboxColors.danger),
              SboxSeries(name: 'Hủy', values: [for (final c in byCarrier) n(c['cancelled'])], color: SboxColors.slate400),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Trạng thái vận đơn',
          child: SboxDonutChart(
            valueFormat: (v) => '${SboxFmt.number(v)} đơn',
            centerValue: SboxFmt.number(n(t['shipments'])),
            centerLabel: 'vận đơn',
            maxSlices: 6,
            slices: [
              SboxSlice('Đã giao', n(t['delivered']), color: SboxColors.success),
              SboxSlice('Đang giao / chờ', other, color: SboxColors.brand500),
              SboxSlice('Giao thất bại', n(t['failedOrders']), color: SboxColors.warning),
              SboxSlice('Hoàn hàng', n(t['returning']) + n(t['returned']), color: SboxColors.danger),
              SboxSlice('Hủy', n(t['cancelled']), color: SboxColors.slate400),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summary(Map<String, dynamic> t) {
    Widget cell(String label, String value, {Color? color}) => Container(
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: SboxColors.surface,
            borderRadius: BorderRadius.circular(SboxRadius.md),
            border: Border.all(color: SboxColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.textMuted)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color ?? SboxColors.text)),
          ]),
        );
    final profit = _n(t['shipProfit']);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      cell('Vận đơn', '${_n(t['shipments'])}'),
      cell('Đã giao', '${_n(t['delivered'])} · ${_n(t['successRate'])}%', color: SboxColors.success),
      cell('Giao thất bại', '${_n(t['failedOrders'])} đơn / ${_n(t['failedAttempts'])} lượt', color: SboxColors.warning),
      cell('Hoàn hàng', '${_n(t['returning'])} đang · ${_n(t['returned'])} đã về', color: SboxColors.danger),
      cell('Hủy vận đơn', '${_n(t['cancelled'])}'),
      cell('TG giao TB', t['avgDeliveryHours'] == null ? '—' : '${_n(t['avgDeliveryHours'])} giờ'),
      cell('Phí thu khách', _money.format(_n(t['feeCharged']))),
      cell('Cước shop chịu', _money.format(_n(t['carrierCost']))),
      cell('Lãi/lỗ ship', _money.format(profit), color: profit < 0 ? SboxColors.danger : SboxColors.success),
      cell('COD chưa đối soát', _money.format(_n(t['codPending'])), color: SboxColors.warningText),
    ]);
  }

  List<Widget> _tabBody(List<Map<String, dynamic>> byCarrier) {
    switch (_tab) {
      case 0:
        if (byCarrier.isEmpty) return [_empty('Chưa có vận đơn trong khoảng thời gian này')];
        return [
          for (final c in byCarrier)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['carrierName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(tr('${_n(c['shipments'])} vận đơn · giao ${_n(c['delivered'])} (${_n(c['successRate'])}%) · '
                      'thất bại ${_n(c['failedOrders'])} · hoàn ${_n(c['returning']) + _n(c['returned'])} · hủy ${_n(c['cancelled'])}')),
                  Text(tr('TG giao TB: ${c['avgDeliveryHours'] == null ? '—' : '${_n(c['avgDeliveryHours'])} giờ'} · '
                      'Lãi/lỗ ship: ${_money.format(_n(c['shipProfit']))} · COD chưa đối soát: ${_money.format(_n(c['codPending']))}'),
                      style: const TextStyle(fontSize: 12, color: SboxColors.textSecondary)),
                ]),
              ),
            ),
        ];
      case 1:
        return _rows(_maps(_data?['failed']), (r) => tr('Thất bại ${_n(r['failCount'])} lần${r['reason'] != null ? ' · ${r['reason']}' : ''}'));
      case 2:
        return _rows(_maps(_data?['returns']), (r) {
          final received = r['returnReceivedAt'] != null;
          return tr('${r['statusLabel']}${r['returnedAt'] != null ? ' ${_t(r['returnedAt'])}' : ''}'
              '${received ? ' · shop đã nhận ${_t(r['returnReceivedAt'])}' : ' · shop CHƯA xác nhận nhận hàng'}');
        }, action: (r) => r['returnReceivedAt'] == null
            ? TextButton(onPressed: () => _confirmReturn(r), child: Text(tr('Đã nhận hàng')))
            : null);
      case 3:
        return _rows(_maps(_data?['cancelled']), (r) => tr('Hủy ${_t(r['cancelledAt'])}${r['reason'] != null ? ' · ${r['reason']}' : ''}'));
      default:
        final cod = _maps(_data?['cod']);
        return [
          if (cod.any((r) => r['codSettledAt'] == null))
            Row(children: [
              Expanded(child: Text(tr('Chọn đơn hãng đã chuyển tiền rồi bấm «Đã đối soát»'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.textMuted))),
              FilledButton.icon(
                onPressed: _codPicked.isEmpty ? null : _settleCod,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(tr('Đã đối soát (${_codPicked.length})')),
              ),
            ]),
          ..._rows(cod, (r) => tr('COD ${_money.format(_n(r['codAmount']))}'
              '${r['codSettledAt'] != null ? ' · đã đối soát ${_t(r['codSettledAt'])}' : ' · chưa đối soát'}'),
              leading: (r) => r['codSettledAt'] != null
                  ? const Icon(Icons.check_circle, color: SboxColors.success)
                  : Checkbox(
                      value: _codPicked.contains('${r['orderId']}'),
                      onChanged: (v) => setState(() => v == true
                          ? _codPicked.add('${r['orderId']}')
                          : _codPicked.remove('${r['orderId']}')),
                    )),
        ];
    }
  }

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(tr(msg), style: const TextStyle(color: SboxColors.textMuted))),
      );

  List<Widget> _rows(
    List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>) detail, {
    Widget? Function(Map<String, dynamic>)? action,
    Widget? Function(Map<String, dynamic>)? leading,
  }) {
    if (rows.isEmpty) return [_empty('Không có đơn')];
    return [
      for (final r in rows)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: leading?.call(r),
            title: Text(tr('${r['orderNo']} · ${r['customerName'] ?? 'Khách'} · ${r['carrierName']}')),
            subtitle: Text('${r['trackingCode'] ?? ''}  ${detail(r)}'),
            trailing: action?.call(r),
            onTap: () => unawaited(PosReportOpen.sale(context, '${r['orderId']}')),
          ),
        ),
    ];
  }
}
