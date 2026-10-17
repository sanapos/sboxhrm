import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/api_datetime.dart';
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
  final _qty = NumberFormat('#,##0.##', 'vi_VN');
  final _dt = DateFormat('dd/MM HH:mm');
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;
  /// Nhân viên đang chọn — chỉ lọc phần chi tiết; bảng tổng và các ô số liệu giữ cả cửa hàng
  /// (trước đây chọn một người thì bảng chỉ còn người đó, muốn xem người khác phải bỏ chọn).
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosStaffCommissionReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (_employeeId != null && !_maps(_data?['byStaff']).any((e) => _idOf(e) == _employeeId)) {
        _employeeId = null;
      }
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
  dynamic _f(Map<String, dynamic> e, String camel) =>
      e[camel] ?? e['${camel[0].toUpperCase()}${camel.substring(1)}'];
  String _idOf(Map<String, dynamic> e) => '${_f(e, 'employeeId') ?? ''}';

  static String _modeVi(String? m) => switch (m) {
        'PercentOfLine' => '% doanh thu',
        'FixedPerUnit' => 'Cố định / đơn vị',
        'PercentOfCatalog' => '% giá niêm yết',
        _ => '—',
      };

  String _when(dynamic raw) {
    final d = parseApiUtcDateTime(raw);
    return d == null ? '' : _dt.format(d);
  }

  @override
  Widget build(BuildContext context) {
    final staff = _maps(_data?['byStaff']);
    final products = _maps(_data?['byProduct']);
    final allLines = _maps(_data?['lines']);
    final lines = _employeeId == null ? allLines : allLines.where((e) => _idOf(e) == _employeeId).toList();
    final selectedName = _employeeId == null
        ? null
        : staff.where((e) => _idOf(e) == _employeeId).map((e) => '${_f(e, 'employeeName') ?? ''}').firstOrNull;
    final onlySelf = _data?['onlySelf'] == true;
    final pctOf = _n(_data?['totalRevenue']) > 0 ? _n(_data?['totalCommission']) / _n(_data?['totalRevenue']) * 100 : 0;

    return PosReportMobileScaffold(
      title: 'Hoa hồng nhân viên',
      exportModule: 'PosReportStaffCommission',
      time: _time,
      pngKey: _pngKey,
      filterBar: selectedName == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.badge_outlined, size: 18),
                label: Text(tr('Chi tiết của: $selectedName')),
                onDeleted: () => setState(() => _employeeId = null),
              ),
            ),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_HoaHongNV',
      )),
      onTimeChanged: (t) {
        setState(() => _time = t);
        _load();
      },
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Hoa hồng nhân viên',
        sheetName: 'Hoa hong',
        filePrefix: 'POS_HoaHongNV',
        periodLabel: _time.exportLabel,
        filterLabel: selectedName,
        headers: const [
          'Thời gian',
          'Số HĐ',
          'Nhân viên',
          'Hàng / DV',
          'Combo',
          'SL',
          'SL khách trả',
          'Doanh thu',
          'Cách tính',
          '%',
          'Cố định',
          'Hoa hồng',
        ],
        rows: [
          for (final e in lines)
            [
              _when(_f(e, 'saleAt')),
              '${_f(e, 'orderNo') ?? ''}',
              '${_f(e, 'employeeName') ?? ''}',
              '${_f(e, 'productName') ?? ''}',
              '${_f(e, 'comboName') ?? ''}',
              _n(_f(e, 'qty')),
              _n(_f(e, 'returnedQty')),
              _n(_f(e, 'revenueAmount')),
              _modeVi('${_f(e, 'commissionMode')}'),
              _n(_f(e, 'commissionPercent')),
              _n(_f(e, 'commissionFixed')),
              _n(_f(e, 'commissionAmount')),
            ],
        ],
        summaryLines: [
          for (final e in staff)
            '${_f(e, 'employeeName') ?? '—'}: HH ${_money.format(_n(e['commission']))} · DT ${_money.format(_n(e['revenue']))}',
          'Tổng HH: ${_money.format(_n(_data?['totalCommission']))}',
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (onlySelf)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(tr('Bạn đang xem hoa hồng của chính mình.'),
                        style: SboxType.smallStyle(SboxColors.textMuted)),
                  ),
                SboxInsightPanel(
                  kpis: [
                    SboxKpi(label: 'Tổng hoa hồng', value: SboxFmt.money(_n(_data?['totalCommission'])), icon: Icons.handshake_outlined, tone: SboxTone.success,
                        note: _time.displayLabel),
                    SboxKpi(label: 'Doanh thu tính HH', value: SboxFmt.money(_n(_data?['totalRevenue'])), icon: Icons.payments_outlined),
                    SboxKpi(label: 'Nhân viên hưởng', value: SboxFmt.number(_n(_data?['staffCount'])), icon: Icons.badge_outlined, tone: SboxTone.violet),
                    SboxKpi(label: 'Tỷ lệ HH / doanh thu', value: SboxFmt.pct(pctOf), icon: Icons.percent_rounded, tone: SboxTone.neutral),
                  ],
                  charts: [
                    SboxChartCard(
                      title: 'Hoa hồng theo nhân viên',
                      child: SboxRankList(color: SboxColors.success, maxItems: 8, items: [
                        for (final e in staff)
                          SboxSlice('${_f(e, 'employeeName') ?? '—'}', _n(e['commission']).toDouble(), caption: '${_n(e['orderCount']).toInt()} HĐ'),
                      ]),
                    ),
                    SboxChartCard(
                      title: 'Hoa hồng theo hàng / dịch vụ',
                      child: SboxDonutChart(
                        centerValue: SboxFmt.compact(_n(_data?['totalCommission'])),
                        centerLabel: 'Hoa hồng',
                        slices: [for (final e in products) SboxSlice('${_f(e, 'productName') ?? '—'}', _n(e['commission']).toDouble())],
                      ),
                    ),
                  ],
                ),
                Text(tr('Theo nhân viên · bấm để xem chi tiết của người đó'), style: SboxType.titleSmStyle()),
                const SizedBox(height: 8),
                SboxCard(
                  padding: EdgeInsets.zero,
                  child: SboxDataTable<Map<String, dynamic>>(
                    rows: staff,
                    paginate: false,
                    emptyTitle: 'Chưa có hoa hồng trong kỳ',
                    selectedRow: staff.where((e) => _idOf(e) == _employeeId).firstOrNull,
                    onRowTap: (e) => setState(() => _employeeId = _employeeId == _idOf(e) ? null : _idOf(e)),
                    columns: [
                      SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (e) => '${_f(e, 'employeeName') ?? '—'}'),
                      SboxColumn(label: 'Số HĐ', numeric: true, flex: 1, text: (e) => SboxFmt.number(_n(e['orderCount'])), sortValue: (e) => _n(e['orderCount'])),
                      SboxColumn(label: 'SL', numeric: true, flex: 1, hideOnMobile: true, text: (e) => _qty.format(_n(e['qty']))),
                      SboxColumn(label: 'Doanh thu', numeric: true, flex: 2, text: (e) => SboxFmt.money(_n(e['revenue'])), sortValue: (e) => _n(e['revenue'])),
                      SboxColumn(label: 'Hoa hồng', numeric: true, flex: 2, text: (e) => SboxFmt.money(_n(e['commission'])), sortValue: (e) => _n(e['commission'])),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('Theo hàng / dịch vụ'), style: SboxType.titleSmStyle()),
                const SizedBox(height: 8),
                SboxCard(
                  padding: EdgeInsets.zero,
                  child: SboxDataTable<Map<String, dynamic>>(
                    rows: products,
                    paginate: true,
                    pageSize: 10,
                    emptyTitle: 'Chưa có dữ liệu',
                    columns: [
                      SboxColumn(label: 'Hàng / dịch vụ', primary: true, flex: 3, text: (e) => '${_f(e, 'productName') ?? '—'}'),
                      SboxColumn(label: 'SL', numeric: true, flex: 1, text: (e) => _qty.format(_n(e['qty']))),
                      SboxColumn(label: 'Doanh thu', numeric: true, flex: 2, hideOnMobile: true, text: (e) => SboxFmt.money(_n(e['revenue']))),
                      SboxColumn(label: 'Hoa hồng', numeric: true, flex: 2, text: (e) => SboxFmt.money(_n(e['commission'])), sortValue: (e) => _n(e['commission'])),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr(selectedName == null ? 'Chi tiết phiếu (${lines.length})' : 'Chi tiết phiếu · $selectedName (${lines.length})'),
                    style: SboxType.titleSmStyle()),
                const SizedBox(height: 8),
                SboxCard(
                  padding: EdgeInsets.zero,
                  child: SboxDataTable<Map<String, dynamic>>(
                    rows: lines,
                    paginate: true,
                    pageSize: 20,
                    emptyTitle: 'Không có dòng hoa hồng',
                    onRowTap: (e) => unawaited(PosReportOpen.sale(context, '${_f(e, 'saleOrderId') ?? ''}')),
                    columns: [
                      SboxColumn(label: 'Thời gian', minWidth: 100, text: (e) => _when(_f(e, 'saleAt'))),
                      SboxColumn(
                        label: 'Hàng / DV',
                        primary: true,
                        flex: 3,
                        minWidth: 180,
                        cell: (e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${_f(e, 'productName') ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                          Text(
                            [
                              _f(e, 'orderNo'),
                              _f(e, 'employeeName'),
                              if ('${_f(e, 'comboName') ?? ''}'.isNotEmpty) 'combo ${_f(e, 'comboName')}',
                            ].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SboxType.smallStyle(SboxColors.textMuted),
                          ),
                        ]),
                      ),
                      SboxColumn(
                        label: 'SL',
                        numeric: true,
                        minWidth: 90,
                        text: (e) {
                          final ret = _n(_f(e, 'returnedQty'));
                          return '${_qty.format(_n(_f(e, 'qty')))}${ret > 0 ? ' (trả ${_qty.format(ret)})' : ''}';
                        },
                      ),
                      SboxColumn(label: 'Cách tính', minWidth: 110, hideOnMobile: true, text: (e) => _modeVi('${_f(e, 'commissionMode')}')),
                      SboxColumn(label: 'Doanh thu', numeric: true, minWidth: 110, hideOnMobile: true,
                          text: (e) => SboxFmt.money(_n(_f(e, 'revenueAmount')))),
                      SboxColumn(label: 'Hoa hồng', numeric: true, minWidth: 110,
                          text: (e) => SboxFmt.money(_n(_f(e, 'commissionAmount')))),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
