import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hoa hồng theo NV làm hàng/DV / thành phần combo.
class PosStaffCommissionReportScreen extends StatefulWidget {
  const PosStaffCommissionReportScreen({super.key});

  @override
  State<PosStaffCommissionReportScreen> createState() =>
      _PosStaffCommissionReportScreenState();
}

class _PosStaffCommissionReportScreenState
    extends State<PosStaffCommissionReportScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosStaffCommissionReport(
      from: _time.from,
      to: _time.to,
      employeeId: _employeeId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final staff = _maps(_data?['byStaff']);
    final products = _maps(_data?['byProduct']);
    final lines = _maps(_data?['lines']);
    return PosReportMobileScaffold(
      title: 'Hoa hồng nhân viên',
      time: _time,
      pngKey: _pngKey,
      onTimeChanged: (t) {
        setState(() => _time = t);
        _load();
      },
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Hoa hồng nhân viên',
        sheetName: 'Hoa hong',
        filePrefix: 'POS_HoaHongNV',
        periodLabel: _time.displayLabel,
        headers: const [
          'Số HĐ',
          'Nhân viên',
          'Hàng / DV',
          'Combo',
          'SL',
          'Doanh thu',
          'Hoa hồng',
        ],
        rows: [
          for (final e in lines)
            [
              '${e['orderNo'] ?? e['OrderNo'] ?? ''}',
              '${e['employeeName'] ?? e['EmployeeName'] ?? ''}',
              '${e['productName'] ?? e['ProductName'] ?? ''}',
              '${e['comboName'] ?? e['ComboName'] ?? ''}',
              _n(e['qty'] ?? e['Qty']),
              _n(e['revenueAmount'] ?? e['RevenueAmount']),
              _n(e['commissionAmount'] ?? e['CommissionAmount']),
            ],
        ],
        summaryLines: [
          'Tổng HH: ${_money.format(_n(_data?['totalCommission']))}',
          'Tổng DT phân bổ: ${_money.format(_n(_data?['totalRevenue']))}',
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                SboxInsightPanel(
                  kpis: [
                    SboxKpi(label: 'Tổng hoa hồng', value: SboxFmt.money(_n(_data?['totalCommission'])), icon: Icons.handshake_outlined, tone: SboxTone.success,
                        note: _time.displayLabel),
                    SboxKpi(label: 'Doanh thu tính HH', value: SboxFmt.money(_n(_data?['totalRevenue'])), icon: Icons.payments_outlined),
                    SboxKpi(label: 'Nhân viên hưởng', value: SboxFmt.number(_n(_data?['staffCount'])), icon: Icons.badge_outlined, tone: SboxTone.violet),
                    SboxKpi(
                        label: 'Tỷ lệ HH / doanh thu',
                        value: SboxFmt.pct(_n(_data?['totalRevenue']) > 0 ? _n(_data?['totalCommission']) / _n(_data?['totalRevenue']) * 100 : 0),
                        icon: Icons.percent_rounded,
                        tone: SboxTone.neutral),
                  ],
                  charts: [
                    SboxChartCard(
                      title: 'Hoa hồng theo nhân viên',
                      child: SboxRankList(color: SboxColors.success, maxItems: 8, items: [
                        for (final e in staff)
                          SboxSlice('${e['employeeName'] ?? e['EmployeeName'] ?? '—'}', _n(e['commission']).toDouble(), caption: '${_n(e['orderCount']).toInt()} HĐ'),
                      ]),
                    ),
                    SboxChartCard(
                      title: 'Hoa hồng theo hàng / dịch vụ',
                      child: SboxDonutChart(
                        centerValue: SboxFmt.compact(_n(_data?['totalCommission'])),
                        centerLabel: 'Hoa hồng',
                        slices: [for (final e in products) SboxSlice('${e['productName'] ?? e['ProductName'] ?? '—'}', _n(e['commission']).toDouble())],
                      ),
                    ),
                  ],
                ),
                Text(tr('Theo nhân viên · bấm để lọc chi tiết'), style: SboxType.titleSmStyle()),
                const SizedBox(height: 8),
                SboxDataTable<Map<String, dynamic>>(
                  rows: staff,
                  paginate: false,
                  emptyTitle: 'Chưa có hoa hồng trong kỳ',
                  selectedRow: staff.where((e) => '${e['employeeId'] ?? e['EmployeeId'] ?? ''}' == _employeeId).firstOrNull,
                  onRowTap: (e) {
                    final id = '${e['employeeId'] ?? e['EmployeeId'] ?? ''}';
                    setState(() => _employeeId = _employeeId == id ? null : id);
                    _load();
                  },
                  columns: [
                    SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (e) => '${e['employeeName'] ?? e['EmployeeName'] ?? '—'}'),
                    SboxColumn(label: 'Số HĐ', numeric: true, flex: 1, text: (e) => SboxFmt.number(_n(e['orderCount'])), sortValue: (e) => _n(e['orderCount'])),
                    SboxColumn(label: 'Doanh thu', numeric: true, flex: 2, text: (e) => SboxFmt.money(_n(e['revenue'])), sortValue: (e) => _n(e['revenue'])),
                    SboxColumn(label: 'Hoa hồng', numeric: true, flex: 2, text: (e) => SboxFmt.money(_n(e['commission'])), sortValue: (e) => _n(e['commission'])),
                  ],
                ),
                const SizedBox(height: 12),
                Text(tr('Theo hàng / dịch vụ'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ...products.map((e) => ListTile(
                      dense: true,
                      title: Text(tr('${e['productName'] ?? e['ProductName'] ?? '—'}')),
                      subtitle: Text(tr('SL ${_n(e['qty'])}')),
                      trailing: Text(_money.format(_n(e['commission']))),
                    )),
                const SizedBox(height: 12),
                Text(tr('Chi tiết phiếu'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ...lines.map((e) => ListTile(
                      dense: true,
                      title: Text(tr(
                          '${e['productName'] ?? ''} · ${e['employeeName'] ?? ''}')),
                      subtitle: Text(tr(
                          '${e['orderNo'] ?? ''} ${e['comboName'] != null ? '· ${e['comboName']}' : ''}')),
                      trailing: Text(
                        _money.format(_n(e['commissionAmount'] ?? e['CommissionAmount'])),
                      ),
                      onTap: () => unawaited(PosReportOpen.sale(
                          context, '${e['saleOrderId'] ?? e['SaleOrderId'] ?? ''}')),
                    )),
              ],
            ),
    );
  }
}
