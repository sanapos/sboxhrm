import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
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
                Text(
                  tr('Tổng hoa hồng ${_money.format(_n(_data?['totalCommission']))} · ${_n(_data?['staffCount'])} NV'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(tr('Theo nhân viên'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ...staff.map((e) {
                  final id = '${e['employeeId'] ?? e['EmployeeId'] ?? ''}';
                  final selected = _employeeId == id;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    title: Text(tr('${e['employeeName'] ?? e['EmployeeName'] ?? '—'}')),
                    subtitle: Text(tr(
                        '${_n(e['orderCount'])} HĐ · DT ${_money.format(_n(e['revenue']))}')),
                    trailing: Text(
                      _money.format(_n(e['commission'])),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      setState(() => _employeeId = selected ? null : id);
                      _load();
                    },
                  );
                }),
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
