import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_report.dart';
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
/// Đặt chỗ / cọc theo kỳ.
class PosReservationReportScreen extends StatefulWidget {
  const PosReservationReportScreen({super.key, this.title = 'Đặt chỗ / cọc', this.profile});

  /// Tên theo ngành từ trang Báo cáo («Đặt lịch & cọc», «Đặt bàn & cọc»…).
  final String title;

  /// Ngành bán — chữ «bàn» trên báo cáo đổi thành «ghế» / «phòng»; null = «bàn» như cũ.
  final PosSellProfile? profile;

  @override
  State<PosReservationReportScreen> createState() =>
      _PosReservationReportScreenState();
}

class _PosReservationReportScreenState extends State<PosReservationReportScreen> {
  final _pngKey = GlobalKey();
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM HH:mm');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  String? _status;
  String _dateBasis = 'usage';
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosReservationsReport(
      from: _time.from,
      to: _time.to,
      status: _status,
      dateBasis: _dateBasis,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  /// «bàn» / «ghế» / «phòng»; rỗng với ngành không có chỗ ngồi (gym) → nói theo «khách đến».
  String get _noun {
    final p = widget.profile;
    if (p == null) return 'bàn';
    if (p == PosSellProfile.gym) return '';
    return p.resourceNoun.isEmpty ? 'bàn' : p.resourceNoun;
  }

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return PosReportMobileScaffold(
      pngKey: _pngKey,
      onExportExcel: _data == null ? null : () => unawaited(_exportExcel(items)),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_DatCho',
      )),
      title: widget.title,
      exportModule: 'PosSalesReport',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? ListView(children: const [
              SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: PosTheme.kiotBlue))),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: Text(tr(_noun.isEmpty ? 'Theo ngày đến' : 'Theo ngày dùng $_noun')),
                      selected: _dateBasis == 'usage',
                      onSelected: (_) {
                        setState(() => _dateBasis = 'usage');
                        _load();
                      },
                    ),
                    FilterChip(
                      label: Text(tr('Theo ngày nhận lịch')),
                      selected: _dateBasis == 'created',
                      onSelected: (_) {
                        setState(() => _dateBasis = 'created');
                        _load();
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Text(
                    tr(_dateBasis == 'created'
                        ? 'Lịch nhân viên nhận trong kỳ. Cọc vẫn vào két ngày thu. Lịch dùng sau kỳ: ${_data?['useLaterCount'] ?? 0}.'
                        : 'Lịch khách đến dùng trong kỳ. Đặt trước từ ngày khác: ${_data?['advanceCount'] ?? 0}.'),
                    style: const TextStyle(
                        fontSize: 12, color: PosTheme.textSecondary),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in [
                      (null, 'Tất cả'),
                      ('Booked', 'Đặt ${_data?['bookedCount'] ?? 0}'),
                      ('Seated', 'Nhận ${_data?['seatedCount'] ?? 0}'),
                      ('Cancelled', 'Hủy ${_data?['cancelledCount'] ?? 0}'),
                      ('NoShow', 'Không đến ${_data?['noShowCount'] ?? 0}'),
                    ])
                      FilterChip(
                        label: Text(tr(e.$2)),
                        selected: _status == e.$1,
                        onSelected: (_) {
                          setState(() => _status = e.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SboxInsightPanel(
                  kpis: [
                    SboxKpi(label: 'Cọc đang giữ', value: SboxFmt.money(_n(_data?['depositHeld'])), icon: Icons.lock_clock_outlined),
                    SboxKpi(label: 'Đã trừ vào HĐ', value: SboxFmt.money(_n(_data?['depositApplied'])), icon: Icons.receipt_long_outlined, tone: SboxTone.success),
                    SboxKpi(label: 'Hoàn cọc', value: SboxFmt.money(_n(_data?['depositRefunded'])), icon: Icons.undo_rounded, tone: SboxTone.violet),
                    SboxKpi(label: 'Phạt / mất cọc', value: SboxFmt.money(_n(_data?['depositForfeited'])), icon: Icons.money_off_outlined, tone: SboxTone.danger),
                  ],
                  charts: [
                    SboxChartCard(
                      title: 'Tình trạng lịch đặt',
                      child: SboxDonutChart(
                        valueFormat: (v) => '${SboxFmt.number(v)} lịch',
                        slices: [
                          SboxSlice('Đã đặt', _n(_data?['bookedCount']).toDouble()),
                          SboxSlice(_noun.isEmpty ? 'Khách đã đến' : 'Đã nhận $_noun', _n(_data?['seatedCount']).toDouble(), color: SboxColors.success),
                          SboxSlice('Hủy', _n(_data?['cancelledCount']).toDouble(), color: SboxColors.slate400),
                          SboxSlice('Không đến', _n(_data?['noShowCount']).toDouble(), color: SboxColors.danger),
                        ],
                      ),
                    ),
                  ],
                ),
                PosReportCard(
                  title: 'Lịch (${items.length})',
                  child: items.isEmpty
                      ? Text(tr('Chưa có đặt chỗ'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 16),
                              _row(items[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  static const _statusFilterLabels = {
    'Booked': 'Đã đặt',
    'Seated': 'Đã nhận',
    'Cancelled': 'Hủy',
    'NoShow': 'Không đến',
  };

  /// Xuất đúng danh sách lịch đang hiển thị (theo kỳ, mốc ngày và trạng thái đang lọc).
  Future<void> _exportExcel(List<Map<String, dynamic>> items) async {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    String dt(dynamic v) {
      final d = parseApiUtcDateTime(v);
      return d == null ? '' : fmt.format(d.toLocal());
    }

    final resourceHeader = _noun.isEmpty
        ? 'Bàn / phòng'
        : '${_noun[0].toUpperCase()}${_noun.substring(1)}';
    await PosReportExport.excel(
      context: context,
      title: widget.title,
      sheetName: 'Đặt chỗ',
      filePrefix: 'POS_DatCho',
      periodLabel: _time.exportLabel,
      filterLabel: [
        _dateBasis == 'created'
            ? 'Theo ngày nhận lịch'
            : (_noun.isEmpty ? 'Theo ngày đến' : 'Theo ngày dùng $_noun'),
        'Trạng thái: ${_status == null ? 'Tất cả' : (_statusFilterLabels[_status] ?? _status)}',
      ].join(' · '),
      headers: [
        'STT', 'Ngày giờ dùng', 'Đến', 'Ngày nhận lịch', 'Khách hàng', 'SĐT', resourceHeader, 'Số khách',
        'Trạng thái', 'Tiền cọc yêu cầu', 'Đã cọc', 'Hình thức cọc', 'Tình trạng cọc', 'Dịp', 'Yêu cầu đặc biệt', 'Ghi chú',
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          () {
            final r = items[i];
            return <dynamic>[
              i + 1,
              dt(r['reservedAt']),
              dt(r['reservedUntil']),
              dt(r['createdAt']),
              '${r['customerName'] ?? ''}',
              '${r['phone'] ?? ''}',
              '${r['resourceName'] ?? r['resourceCode'] ?? ''}',
              _n(r['guestCount']).toInt(),
              '${r['statusLabel'] ?? r['status'] ?? ''}',
              _n(r['depositAmount']),
              _n(r['depositPaid']),
              '${r['depositPaymentMethod'] ?? ''}',
              '${r['depositStatusLabel'] ?? r['depositStatus'] ?? ''}',
              '${r['occasionLabel'] ?? ''}',
              '${r['specialRequest'] ?? ''}',
              '${r['note'] ?? ''}',
            ];
          }(),
      ],
      summaryLines: [
        'Tổng lịch: ${items.length}',
        'Cọc đang giữ: ${_moneyFmt.format(_n(_data?['depositHeld']))}',
        'Đã trừ vào HĐ: ${_moneyFmt.format(_n(_data?['depositApplied']))}',
        'Hoàn cọc: ${_moneyFmt.format(_n(_data?['depositRefunded']))}',
        'Phạt / mất cọc: ${_moneyFmt.format(_n(_data?['depositForfeited']))}',
      ],
    );
  }

  ///Lịch đã trừ cọc vào hóa đơn → bấm mở hóa đơn đó.
  Widget _row(Map<String, dynamic> r) {
    final orderId = '${r['depositAppliedOrderId'] ?? ''}';
    final body = _rowBody(r);
    if (orderId.isEmpty || orderId.startsWith('0000')) return body;
    return InkWell(
      onTap: () => PosReportOpen.sale(context, orderId),
      child: Row(children: [
        Expanded(child: body),
        const Icon(Icons.receipt_long_outlined, size: 18, color: PosTheme.kiotBlue),
      ]),
    );
  }

  Widget _rowBody(Map<String, dynamic> r) {
    final at = parseApiUtcDateTime(r['reservedAt']);
    final created = parseApiUtcDateTime(r['createdAt']);
    final occ = (r['occasionLabel'] ?? '').toString();
    final req = (r['specialRequest'] ?? '').toString();
    final note = (r['note'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('${r['resourceName'] ?? r['resourceCode'] ?? 'Bàn'} · ${r['customerName'] ?? ''}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              tr(r['statusLabel']?.toString() ?? r['status']?.toString() ?? ''),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ],
        ),
        Text(
          tr([
            if (at != null) 'Dùng ${_dateFmt.format(at.toLocal())}',
            if (created != null) 'Đặt ${DateFormat('dd/MM HH:mm').format(created.toLocal())}',
            '${r['guestCount'] ?? 1} khách',
            'cọc ${_moneyFmt.format(_n(r['depositPaid']))}',
            if ((r['depositPaymentMethod'] ?? '').toString().isNotEmpty)
              r['depositPaymentMethod'].toString(),
            r['depositStatusLabel'] ?? r['depositStatus'] ?? '',
          ].join(' · ')),
          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
        ),
        if (occ.isNotEmpty || req.isNotEmpty || note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              tr([
                if (occ.isNotEmpty) occ,
                if (req.isNotEmpty) req,
                if (note.isNotEmpty) note,
              ].join(' · ')),
              style: const TextStyle(fontSize: 12, color: SboxColors.violet),
            ),
          ),
      ],
    );
  }
}
