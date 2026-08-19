import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Đặt chỗ / cọc theo kỳ.
class PosReservationReportScreen extends StatefulWidget {
  const PosReservationReportScreen({super.key});

  @override
  State<PosReservationReportScreen> createState() =>
      _PosReservationReportScreenState();
}

class _PosReservationReportScreenState extends State<PosReservationReportScreen> {
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

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return PosReportMobileScaffold(
      title: 'Đặt chỗ / cọc',
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
                      label: Text(tr('Theo ngày dùng bàn')),
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
                PosReportCard(
                  title: 'Cọc',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (label: 'Đang giữ', value: _n(_data?['depositHeld']), color: const Color(0xFF0F766E)),
                      (label: 'Đã trừ HĐ', value: _n(_data?['depositApplied']), color: PosTheme.kiotBlue),
                      (label: 'Hoàn cọc', value: _n(_data?['depositRefunded']), color: const Color(0xFF7C3AED)),
                      (label: 'Phạt / mất', value: _n(_data?['depositForfeited']), color: Colors.red.shade700),
                    ],
                  ),
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

  Widget _row(Map<String, dynamic> r) {
    final at = DateTime.tryParse('${r['reservedAt'] ?? ''}');
    final created = DateTime.tryParse('${r['createdAt'] ?? ''}');
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED)),
            ),
          ),
      ],
    );
  }
}
