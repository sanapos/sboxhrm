import 'dart:async';

import 'package:flutter/material.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../widgets/reports/report_drill_sheet.dart';
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

  static const _tabs = [
    'Theo hãng', 'Giao thất bại', 'Hoàn hàng', 'Hủy vận đơn', 'Đối soát COD', 'Vận đơn treo', 'Chưa tạo vận đơn',
  ];

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
    final d = parseApiUtcDateTime(iso);
    if (d == null) return '—';
    return _dt.format((d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute)).toLocal());
  }

  // ───────── Chip số liệu → vận đơn tạo ra số đó ─────────
  // Lọc tại chỗ danh sách «all» (mọi vận đơn trong kỳ, ≤ 5.000) theo đúng điều kiện
  // PosShippingService.Summarize ở máy chủ, nên tổng các dòng khớp số trên chip.

  List<Map<String, dynamic>> get _all => _maps(_data?['all']);
  String _st(Map<String, dynamic> r) => '${r['statusCode'] ?? ''}';
  bool _shopPays(Map<String, dynamic> r) => '${r['feePayer'] ?? ''}' != 'customer';
  num _cost(Map<String, dynamic> r) => _n(r['carrierFee']) + _n(r['returnFee']);
  num _fee(Map<String, dynamic> r) =>
      _st(r) != 'cancelled' && _st(r) != 'returned' && _shopPays(r) ? _n(r['deliveryFee']) : 0;

  void _drillShip(
    String title,
    List<Map<String, dynamic>> rows, {
    String Function(Map<String, dynamic> r)? trailing,
    num Function(Map<String, dynamic> r)? amount,
    String? note,
  }) {
    final sum = amount == null ? null : rows.fold<num>(0, (s, r) => s + amount(r));
    showReportDrillSheet(
      context,
      title: title,
      subtitle: [_time.displayLabel, if (_carrier != null) 'hãng $_carrier'].join(' · '),
      note: note,
      total: sum == null ? null : 'Tổng ${_money.format(sum)}',
      footer: _data?['truncated'] == true ? 'Kỳ có hơn 5.000 vận đơn — chỉ tính 5.000 vận đơn mới nhất.' : null,
      emptyText: 'Không có vận đơn',
      rows: [
        for (final r in rows)
          ReportDrillRow(
            title: '${r['orderNo']} · ${r['customerName'] ?? 'Khách'}',
            subtitle: [
              '${r['carrierName'] ?? ''}',
              if ('${r['trackingCode'] ?? ''}'.isNotEmpty) '${r['trackingCode']}',
              '${r['statusLabel'] ?? ''}',
              _t(r['shippedAt']),
            ].where((e) => e.trim().isNotEmpty).join(' · '),
            trailing: trailing?.call(r) ?? (amount == null ? null : _money.format(amount(r))),
            trailingColor: amount != null && amount(r) < 0 ? SboxColors.danger : null,
            icon: Icons.local_shipping_outlined,
            onTap: () => unawaited(PosReportOpen.sale(context, '${r['orderId']}')),
          ),
      ],
    );
  }

  void _drillShipments() => _drillShip('Vận đơn', _all);

  void _drillDelivered(Map<String, dynamic> t) => _drillShip(
        'Giao thành công',
        _all.where((r) => _st(r) == 'delivered').toList(),
        note: 'Tỷ lệ = đã giao ÷ (đã giao + đã hoàn) = ${_n(t['delivered'])} ÷ '
            '(${_n(t['delivered'])} + ${_n(t['returned'])}) = ${_n(t['successRate'])}%. '
            'Không tính vận đơn hủy và vận đơn đang đi.',
      );

  void _drillFailed() => _drillShip(
        'Giao thất bại',
        _maps(_data?['failed']),
        trailing: (r) => '${_n(r['failCount']) > 0 ? _n(r['failCount']) : 1} lượt',
        note: 'Vận đơn có ít nhất một lần giao thất bại hoặc đang ở trạng thái giao thất bại. '
            'Số lượt = cộng cột bên phải.',
      );

  void _drillReturns() => _drillShip('Hoàn hàng', _maps(_data?['returns']));

  void _drillFailedOrReturned(Map<String, dynamic> t) => _drillShip(
        'Thất bại / hoàn',
        [..._maps(_data?['failed']), ..._maps(_data?['returns'])],
        note: 'Giao thất bại ${_n(t['failedOrders'])} + đang hoàn ${_n(t['returning'])} + đã hoàn ${_n(t['returned'])}. '
            'Vận đơn vừa thất bại vừa hoàn được tính ở cả hai nhóm (hiện 2 dòng).',
      );

  void _drillCancelled() => _drillShip('Hủy vận đơn', _maps(_data?['cancelled']));

  void _drillHours(Map<String, dynamic> t) {
    final rows = _all.where((r) => _n(r['deliveryHours']) > 0).toList()
      ..sort((a, b) => _n(b['deliveryHours']).compareTo(_n(a['deliveryHours'])));
    _drillShip(
      'Thời gian giao trung bình',
      rows,
      trailing: (r) => '${_n(r['deliveryHours'])} giờ',
      note: 'TB = tổng giờ (tạo vận đơn → giao xong) ÷ số vận đơn có giờ giao = '
          '${t['avgDeliveryHours'] == null ? '—' : '${_n(t['avgDeliveryHours'])} giờ'} trên ${rows.length} vận đơn.',
    );
  }

  void _drillFeeCharged() => _drillShip(
        'Phí ship thu khách',
        _all.where((r) => _fee(r) != 0).toList(),
        amount: _fee,
        note: 'Phí giao trên đơn của vận đơn không hủy / không hoàn, shop trả cước cho hãng. '
            'Khách trả cước thẳng cho hãng thì không tính.',
      );

  void _drillCarrierCost() => _drillShip(
        'Cước shop chịu',
        _all.where((r) => _st(r) != 'cancelled' && _shopPays(r) && _cost(r) != 0).toList(),
        amount: _cost,
        note: 'Cước hãng + cước hoàn của vận đơn không hủy, shop trả cước.',
      );

  void _drillShipProfit(Map<String, dynamic> t) => _drillShip(
        'Lãi / lỗ phí ship',
        _all.where((r) => _st(r) != 'cancelled' && _shopPays(r) && (_fee(r) - _cost(r)) != 0).toList(),
        amount: (r) => _fee(r) - _cost(r),
        note: 'Lãi / lỗ = Phí thu khách − Cước shop chịu = ${_money.format(_n(t['feeCharged']))} − '
            '${_money.format(_n(t['carrierCost']))} = ${_money.format(_n(t['shipProfit']))}.',
      );

  void _drillCodPending() => _drillShip(
        'COD chưa đối soát',
        _all.where((r) => _st(r) == 'delivered' && r['codSettledAt'] == null && _n(r['codAmount']) != 0).toList(),
        amount: (r) => _n(r['codAmount']),
        note: 'Vận đơn đã giao, hãng chưa chuyển tiền thu hộ. Đối soát ở thẻ «Đối soát COD».',
      );

  Future<void> _confirmReturn(Map<String, dynamic> r) async {
    final feeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận đã nhận hàng hoàn?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Đơn ${r['orderNo']} — hàng sẽ được nhập lại kho và đơn bán bị hủy (trừ doanh thu, công nợ, điểm).')),
          const SizedBox(height: 12),
          TextField(
            controller: feeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('Cước hoàn hãng thu thêm (nếu có)'),
              suffixText: 'đ',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đã nhận hàng'))),
        ],
      ),
    );
    if (ok != true) return;
    final fee = double.tryParse(feeCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final res = await _api.confirmPosShipmentReturn('${r['orderId']}', returnFee: fee);
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
      final errs = ((res['data'] is Map ? (res['data'] as Map)['errors'] : null) as List?)?.map((e) => '$e').toList() ?? const [];
      NotificationOverlayManager().showSuccess(
          title: 'Đã đối soát COD',
          message: tr('${_codPicked.length - errs.length} đơn: đã ghi phiếu thu «Thu hộ COD» vào sổ quỹ, cập nhật đã trả và công nợ khách${errs.isEmpty ? '' : '\n${errs.take(2).join('\n')}'}'));
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
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_VanChuyen',
      )),
      title: 'Báo cáo vận chuyển',
      exportModule: 'PosShipping',
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
                ..._alerts(),
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

  /// Cảnh báo: danh sách bị cắt, COD quá hạn đối soát, vận đơn treo, đơn chưa tạo vận đơn.
  List<Widget> _alerts() {
    // Bấm dòng cảnh báo → danh sách tạo ra số đó (COD quá hạn: sheet; treo / chưa tạo: chuyển thẻ).
    final msgs = <(String, VoidCallback?)>[
      if (_data?['truncated'] == true) ('Kỳ này có hơn 5.000 vận đơn — danh sách bị cắt, hãy thu hẹp khoảng ngày.', null),
      if (_n(_data?['codOverdueCount']) > 0)
        (
          'COD quá 7 ngày chưa đối soát: ${_n(_data?['codOverdueCount'])} đơn · ${_money.format(_n(_data?['codOverdueAmount']))} đ',
          () => _drillShip(
                'COD quá hạn đối soát',
                _maps(_data?['cod']).where(_overdue).toList(),
                amount: (r) => _n(r['codAmount']),
                note: 'Vận đơn giao xong từ 7 ngày trước, hãng chưa chuyển tiền thu hộ.',
              ),
        ),
      if (_maps(_data?['stale']).isNotEmpty)
        ('${_maps(_data?['stale']).length} vận đơn quá 3 ngày không có cập nhật từ hãng', () => setState(() => _tab = 5)),
      if (_maps(_data?['unshipped']).isNotEmpty)
        ('${_maps(_data?['unshipped']).length} đơn giao hàng chưa tạo vận đơn', () => setState(() => _tab = 6)),
    ];
    if (msgs.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(SboxRadius.md),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in msgs)
            InkWell(
              onTap: m.$2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr(m.$1), style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900))),
                  if (m.$2 != null) Icon(Icons.chevron_right, size: 16, color: Colors.orange.shade800),
                ]),
              ),
            ),
        ]),
      ),
    ];
  }

  String _tabCount(int i) {
    final key = ['byCarrier', 'failed', 'returns', 'cancelled', 'cod', 'stale', 'unshipped'][i];
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
        SboxKpi(label: 'Vận đơn', value: SboxFmt.number(n(t['shipments'])), icon: Icons.local_shipping_outlined, note: _time.displayLabel,
            onTap: _drillShipments),
        SboxKpi(label: 'Giao thành công', value: SboxFmt.pct(n(t['successRate'])), icon: Icons.task_alt_rounded, tone: SboxTone.success,
            note: '${SboxFmt.number(n(t['delivered']))} đơn đã giao', onTap: () => _drillDelivered(t)),
        SboxKpi(label: 'Thất bại / hoàn', value: SboxFmt.number(n(t['failedOrders']) + n(t['returning']) + n(t['returned'])),
            icon: Icons.assignment_return_outlined, tone: SboxTone.danger, note: 'Cần gọi khách / nhận hàng hoàn',
            onTap: () => _drillFailedOrReturned(t)),
        SboxKpi(label: 'Lãi / lỗ phí ship', value: SboxFmt.money(profit), icon: Icons.savings_outlined,
            tone: profit < 0 ? SboxTone.danger : SboxTone.brand, note: 'Phí thu khách − cước hãng',
            onTap: () => _drillShipProfit(t)),
        SboxKpi(label: 'COD chưa đối soát', value: SboxFmt.money(n(t['codPending'])), icon: Icons.account_balance_wallet_outlined, tone: SboxTone.warning,
            onTap: _drillCodPending),
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
    Widget cell(String label, String value, {Color? color, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SboxRadius.md),
        child: Container(
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
        ));
    final profit = _n(t['shipProfit']);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      cell('Vận đơn', '${_n(t['shipments'])}', onTap: _drillShipments),
      cell('Đã giao', '${_n(t['delivered'])} · ${_n(t['successRate'])}%', color: SboxColors.success,
          onTap: () => _drillDelivered(t)),
      cell('Giao thất bại', '${_n(t['failedOrders'])} đơn / ${_n(t['failedAttempts'])} lượt', color: SboxColors.warning,
          onTap: _drillFailed),
      cell('Hoàn hàng', '${_n(t['returning'])} đang · ${_n(t['returned'])} đã về', color: SboxColors.danger,
          onTap: _drillReturns),
      cell('Hủy vận đơn', '${_n(t['cancelled'])}', onTap: _drillCancelled),
      cell('TG giao TB', t['avgDeliveryHours'] == null ? '—' : '${_n(t['avgDeliveryHours'])} giờ',
          onTap: () => _drillHours(t)),
      cell('Phí thu khách', _money.format(_n(t['feeCharged'])), onTap: _drillFeeCharged),
      cell('Cước shop chịu', _money.format(_n(t['carrierCost'])), onTap: _drillCarrierCost),
      cell('Lãi/lỗ ship', _money.format(profit), color: profit < 0 ? SboxColors.danger : SboxColors.success,
          onTap: () => _drillShipProfit(t)),
      cell('COD chưa đối soát', _money.format(_n(t['codPending'])), color: SboxColors.warningText,
          onTap: _drillCodPending),
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
      case 5:
        return _rows(_maps(_data?['stale']),
            (r) => tr('${r['statusLabel']} · cập nhật cuối ${_t(r['statusAt'] ?? r['shippedAt'])} — kiểm tra với hãng'));
      case 6:
        return _rows(_maps(_data?['unshipped']),
            (r) => tr('Bán ${_t(r['shippedAt'])}${_n(r['codAmount']) > 0 ? ' · COD ${_money.format(_n(r['codAmount']))}' : ''} — mở đơn để tạo vận đơn'));
      default:
        final cod = _maps(_data?['cod']);
        return [
          if (cod.any((r) => r['codSettledAt'] == null))
            Row(children: [
              Expanded(child: Text(tr('Chọn đơn hãng đã chuyển tiền rồi bấm «Đã đối soát» — hệ thống ghi thu vào sổ quỹ và trừ công nợ khách'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.textMuted))),
              FilledButton.icon(
                onPressed: _codPicked.isEmpty ? null : _settleCod,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(tr('Đã đối soát (${_codPicked.length})')),
              ),
            ]),
          ..._rows(cod, (r) => tr('COD ${_money.format(_n(r['codAmount']))}'
              '${r['codSettledAt'] != null ? ' · đã đối soát ${_t(r['codSettledAt'])}' : ' · chưa đối soát${_overdue(r) ? ' · QUÁ HẠN' : ''}'}'),
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

  /// Giao xong ≥ 7 ngày mà hãng chưa chuyển tiền COD.
  bool _overdue(Map<String, dynamic> r) {
    final d = parseApiUtcDateTime(r['deliveredAt'] ?? r['statusAt']);
    return r['codSettledAt'] == null && d != null && DateTime.now().toUtc().difference(d.toUtc()).inDays >= 7;
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
