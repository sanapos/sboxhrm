import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../utils/pos_einvoice_actions.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Danh sách hóa đơn tải trực tiếp từ hãng (Viettel / Easy) và đối chiếu với đơn POS:
/// HĐ lập ngoài POS, HĐ đã hủy trên hãng nhưng POS chưa biết.
class PosEInvoiceProviderListScreen extends StatefulWidget {
  const PosEInvoiceProviderListScreen({super.key, this.initialTime, this.portal});

  final PosKiotTimeFilterState? initialTime;
  final Map<String, dynamic>? portal;

  @override
  State<PosEInvoiceProviderListScreen> createState() =>
      _PosEInvoiceProviderListScreenState();
}

class _PosEInvoiceProviderListScreenState
    extends State<PosEInvoiceProviderListScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  late PosKiotTimeFilterState _time = widget.initialTime ??
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  String _filter = 'all';

  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosEInvoiceProviderInvoices(
      from: _time.from,
      to: _time.to,
      page: _page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        final raw = _data!['items'];
        _items = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        if (_data!['supported'] == false) _error = _data!['message']?.toString();
      } else {
        _data = null;
        _items = [];
        _error = res['message']?.toString() ?? 'Không tải được danh sách từ hãng';
      }
    });
  }

  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'outside':
        return _items.where((e) => e['orderId'] == null).toList();
      case 'matched':
        return _items.where((e) => e['orderId'] != null).toList();
      case 'mismatch':
        return _items.where((e) => e['statusMismatch'] == true).toList();
      default:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _int(_data?['total']);
    final pages = total <= 0 ? 1 : ((total + _pageSize - 1) ~/ _pageSize);
    final providerName = posEInvoiceProviderName(
        _data?['provider']?.toString() ?? widget.portal?['provider']?.toString());
    return PosReportMobileScaffold(
      title: 'HĐĐT trên $providerName',
      time: _time,
      onTimeChanged: (s) {
        setState(() {
          _time = s;
          _page = 1;
        });
        _load();
      },
      onRefresh: _load,
      onExportExcel: _items.isEmpty
          ? null
          : () => unawaited(PosReportExport.excel(
                context: context,
                title: 'Hóa đơn điện tử trên $providerName',
                sheetName: 'HDDT_hang',
                filePrefix: 'POS_HDDT_HANG',
                periodLabel: _time.displayLabel,
                headers: const [
                  'Số HĐ',
                  'Ký hiệu',
                  'Ngày',
                  'Người mua',
                  'Tổng tiền',
                  'Trạng thái trên hãng',
                  'Đơn POS',
                  'Trạng thái POS',
                ],
                rows: [
                  for (final r in _visible)
                    [
                      r['invoiceNo'] ?? '',
                      r['series'] ?? '',
                      _fmtDate(r['issuedAt']),
                      r['buyerName'] ?? '',
                      _num(r['amount']),
                      r['providerStatus'] ?? '',
                      r['orderNo'] ?? 'Ngoài POS',
                      posEInvoiceStatusLabel(r['localStatus']?.toString()),
                    ],
                ],
              )),
      filterBar: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          children: [
            for (final f in [
              ('all', 'Tất cả'),
              ('matched', 'Khớp đơn POS'),
              ('outside', 'Lập ngoài POS'),
              ('mismatch', 'Lệch trạng thái'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr(f.$2), style: const TextStyle(fontSize: 12)),
                  selected: _filter == f.$1,
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
              ),
            if (widget.portal != null)
              ActionChip(
                avatar: const Icon(Icons.open_in_new, size: 16),
                label: Text(tr('Trang quản lý $providerName'),
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => PosEInvoiceActions.openPortal(widget.portal),
              ),
          ],
        ),
      ),
      body: _loading
          ? ListView(children: const [
              SizedBox(
                height: 240,
                child: Center(
                    child: CircularProgressIndicator(color: PosTheme.kiotBlue)),
              ),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (_error != null)
                  Card(
                    elevation: 0,
                    color: SboxColors.warningSoft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(tr(_error!),
                          style: TextStyle(color: SboxColors.warningText)),
                    ),
                  ),
                if (_data?['supported'] == true)
                  PosReportCard(
                    title: 'Đối chiếu với POS',
                    child: PosReportMetricTiles(
                      tiles: [
                        (
                          label: 'Trên hãng',
                          value: total.toDouble(),
                          color: PosTheme.kiotBlue,
                        ),
                        (
                          label: 'Khớp đơn POS',
                          value: _num(_data?['matchedCount']),
                          color: SboxColors.successText,
                        ),
                        (
                          label: 'Lập ngoài POS',
                          value: _num(_data?['outsidePosCount']),
                          color: SboxColors.warningText,
                        ),
                        (
                          label: 'Lệch trạng thái',
                          value: _num(_data?['mismatchCount']),
                          color: SboxColors.dangerText,
                        ),
                      ],
                    ),
                  ),
                for (final r in _visible) _row(r),
                if (_data?['supported'] == true && pages > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _page > 1
                            ? () {
                                setState(() => _page--);
                                _load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(tr('Trang $_page / $pages')),
                      IconButton(
                        onPressed: _page < pages
                            ? () {
                                setState(() => _page++);
                                _load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  String _fmtDate(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    return d == null ? '' : _dateFmt.format(d.toLocal());
  }

  Widget _row(Map<String, dynamic> r) {
    final matched = r['orderId'] != null;
    final mismatch = r['statusMismatch'] == true;
    final cancelled = r['cancelled'] == true;
    final viewUrl = r['viewUrl']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: mismatch ? SboxColors.danger : const Color(0xFFE8ECF0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: matched
            ? () => unawaited(PosReportOpen.sale(context, r['orderId'].toString()))
            : (viewUrl == null ? null : () => PosEInvoiceActions.openUrl(viewUrl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'HĐ ${r['invoiceNo'] ?? '—'}${(r['series'] ?? '').toString().isEmpty ? '' : ' · ${r['series']}'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  Text(
                    tr((r['providerStatus'] ?? '').toString()),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cancelled
                          ? SboxColors.slate500
                          : SboxColors.successText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r['buyerName'] ?? 'Khách lẻ'} · ${_moneyFmt.format(_num(r['amount']))} · ${_fmtDate(r['issuedAt'])}',
                style: TextStyle(fontSize: 12, color: SboxColors.slate600),
              ),
              const SizedBox(height: 4),
              Text(
                matched
                    ? tr('Đơn POS ${r['orderNo']} · ${posEInvoiceStatusLabel(r['localStatus']?.toString())}'
                        '${mismatch ? ' — hãng đã hủy, cần Đồng bộ' : ''}')
                    : tr('Lập ngoài POS (không có đơn tương ứng)'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: mismatch
                      ? SboxColors.dangerText
                      : matched
                          ? SboxColors.slate700
                          : SboxColors.warningText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
