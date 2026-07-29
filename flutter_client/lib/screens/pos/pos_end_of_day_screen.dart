import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_end_of_day_report.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_end_of_day_print.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

const _kiotBlue = PosTheme.kiotBlue;
final _money = NumberFormat('#,##0', 'vi_VN');
final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Màn hình tổng kết cuối ngày theo nhân viên (bill + A4).
class PosEndOfDayScreen extends StatefulWidget {
  const PosEndOfDayScreen({super.key});

  @override
  State<PosEndOfDayScreen> createState() => _PosEndOfDayScreenState();
}

class _PosEndOfDayScreenState extends State<PosEndOfDayScreen> {
  final _api = ApiService();

  PosKiotTimeFilterState _time = PosKiotTimeFilterState(
    preset: PosKiotTimePreset.today,
    isCustom: false,
  );
  PosEndOfDayPrintFormat _format = PosEndOfDayPrintFormat.bill58;
  String _filterBy = 'soldBy';
  bool _showProductDetail = true;
  bool _loading = false;
  String? _error;
  PosEndOfDayReport? _report;
  List<PosEndOfDayStaff> _staff = [];
  String? _selectedStaffKey;
  bool _canPickStaff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAndLoad());
  }

  Future<void> _initAndLoad() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _canPickStaff = StoreRoleHelper.isManagerOrAbove(auth.userRole);
    await _loadStaff();
    await _loadReport();
  }

  (DateTime?, DateTime?) get _range => _time.resolvedRange;

  Future<void> _loadStaff() async {
    final from = _range.$1;
    final to = _range.$2;
    final res = await _api.getPosEndOfDayStaff(
      from: from,
      to: to,
      filterBy: _filterBy,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      final list = (res['data'] as List)
          .whereType<Map>()
          .map((e) => PosEndOfDayStaff.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _staff = list;
        if (!_canPickStaff && list.isNotEmpty) {
          _selectedStaffKey = _filterBy == 'soldByEmployee'
              ? list.first.employeeId
              : list.first.email;
        } else if (_selectedStaffKey != null &&
            list.every((s) => _staffKey(s) != _selectedStaffKey)) {
          _selectedStaffKey = null;
        }
      });
    }
  }

  String? _staffKey(PosEndOfDayStaff s) =>
      _filterBy == 'soldByEmployee' ? s.employeeId : s.email;

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = _range.$1;
    final to = _range.$2;
    final res = await _api.getPosEndOfDayReport(
      from: from,
      to: to,
      staffEmail: _filterBy != 'soldByEmployee' && _canPickStaff
          ? _selectedStaffKey
          : null,
      soldByEmployeeId:
          _filterBy == 'soldByEmployee' ? _selectedStaffKey : null,
      filterBy: _filterBy,
      includeProductDetail: _showProductDetail,
      includeTransactions: _format == PosEndOfDayPrintFormat.a4,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _report = PosEndOfDayReport.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
        _loading = false;
      });
    }
  }

  Future<void> _applyPreset(PosKiotTimePreset preset) async {
    setState(() => _time = PosKiotTimeFilterState(preset: preset, isCustom: false));
    await _loadStaff();
    await _loadReport();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _time.customFrom ?? now,
        end: _time.customTo ?? now,
      ),
      locale: appUiLocale(),
      helpText: 'Chọn khoảng thời gian',
    );
    if (picked == null || !mounted) return;
    setState(() => _time = PosKiotTimeFilterState(
          isCustom: true,
          customFrom: picked.start,
          customTo: picked.end,
        ));
    await _loadStaff();
    await _loadReport();
  }

  Future<void> _print() async {
    final r = _report;
    if (r == null) return;
    await printPosEndOfDayReport(
      context,
      r,
      format: _format,
      showProductDetail: _showProductDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hideAppBar = HrmPageChrome.usesMainLayoutAppBar;
    final pushed = PosHubScope.pushedSubPageOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: hideAppBar
          ? null
          : AppBar(
              backgroundColor: _kiotBlue,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: pushed,
              title: Text(tr('Tổng kết cuối ngày')),
              actions: [
                IconButton(
                  tooltip: tr('Tải lại'),
                  onPressed: _loading ? null : _loadReport,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(child: _buildBody()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PosTheme.border)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_canPickStaff) ...[
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: _selectedStaffKey,
                  decoration: InputDecoration(
                    labelText: tr('Nhân viên'),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr('Tất cả nhân viên')),
                    ),
                    ..._staff.map((s) => DropdownMenuItem<String?>(
                          value: _staffKey(s),
                          child: Text(tr(s.displayName), overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) async {
                          setState(() => _selectedStaffKey = v);
                          await _loadReport();
                        },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _filterBy,
                  decoration: InputDecoration(
                    labelText: tr('Lọc theo'),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem(value: 'soldBy', child: Text(tr('Người bán'))),
                    DropdownMenuItem(
                        value: 'soldByEmployee', child: Text(tr('NV (hồ sơ)'))),
                    DropdownMenuItem(value: 'createdBy', child: Text(tr('Người tạo'))),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) async {
                          if (v == null) return;
                          setState(() {
                            _filterBy = v;
                            _selectedStaffKey = null;
                          });
                          await _loadStaff();
                          await _loadReport();
                        },
                ),
              ),
            ],
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<PosEndOfDayPrintFormat>(
                value: _format,
                decoration: InputDecoration(
                  labelText: tr('Mẫu in'),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: [
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.bill58,
                    child: Text(tr('Bill K58')),
                  ),
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.bill80,
                    child: Text(tr('Bill K80')),
                  ),
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.a4,
                    child: Text(tr('Khổ A4')),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() => _format = v);
                        if (v == PosEndOfDayPrintFormat.a4) await _loadReport();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kiotBlue));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(_error!), style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadReport, child: Text(tr('Thử lại'))),
          ],
        ),
      );
    }
    final r = _report;
    if (r == null) {
      return Center(child: Text(tr('Không có dữ liệu')));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PosTheme.border),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _format == PosEndOfDayPrintFormat.a4
                  ? _buildA4Preview(r)
                  : _buildBillPreview(r),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBillPreview(PosEndOfDayReport r) {
    final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
    final k58 = _format == PosEndOfDayPrintFormat.bill58;
    final maxW = k58 ? 280.0 : 340.0;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            tr(title),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xFF334155),
            ),
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.storeName != null && r.storeName!.trim().isNotEmpty)
                  Text(
                    tr(r.storeName!.trim()),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(tr('TỔNG KẾT CUỐI NGÀY'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  tr('Bill ${k58 ? 'K58' : 'K80'}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('NV: $staff\n'
                  '${_dt(r.from)} – ${_dt(r.to)}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary, height: 1.35),
                ),
                const Divider(height: 20, thickness: 1.2),
                section('BÁN HÀNG'),
                _summaryLine('', 'Số đơn', '${r.orderCount}'),
                _summaryLine('', 'Doanh thu', _fmt(r.totalSales)),
                _summaryLine('', 'Chiết khấu', _fmt(r.orderDiscount)),
                _summaryLine('', 'VAT', _fmt(r.vat)),
                _summaryLine('', 'DT ròng', _fmt(r.netSales), bold: true),
                const Divider(height: 16),
                section('TRẢ / HỦY'),
                _summaryLine('', 'Trả hàng', _fmt(r.refundTotal)),
                _summaryLine('', 'Sau trả', _fmt(r.totalAfterRefund)),
                _summaryLine('', 'Hủy đơn', '${r.canceledCount}'),
                const Divider(height: 16),
                section('THANH TOÁN'),
                _summaryLine('', 'Tiền mặt', _fmt(r.cashTotal), indent: true),
                _summaryLine('', 'Ghi nợ', _fmt(r.debtTotal), indent: true),
                for (final p in r.payments)
                  if (!p.paymentMethod.toLowerCase().contains('mặt') &&
                      p.paymentMethod.toLowerCase() != 'cash')
                    _summaryLine('', p.paymentMethod, _fmt(p.total), indent: true),
                const Divider(height: 18, thickness: 1.4),
                _summaryLine('', 'THỰC THU', _fmt(r.actualReceived), bold: true),
                const Divider(height: 18, thickness: 1.4),
                if (_showProductDetail && r.products.isNotEmpty) ...[
                  section('HÀNG BÁN'),
                  for (final p in r.products.take(k58 ? 15 : 30))
                    _summaryLine(
                      '',
                      p.productName,
                      '${_qty(p.qty)} · ${_fmt(p.revenue)}',
                      indent: true,
                    ),
                  if (r.lineDiscountTotal > 0)
                    _summaryLine('', 'CK mặt hàng', _fmt(r.lineDiscountTotal)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildA4Preview(PosEndOfDayReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('BÁO CÁO CUỐI NGÀY VỀ BÁN HÀNG'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _summaryLine('', 'Số đơn', '${r.orderCount}'),
        _summaryLine('', 'Doanh thu ròng', _fmt(r.netSales)),
        _summaryLine('', 'Thực thu', _fmt(r.actualReceived), bold: true),
        if (r.transactions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('Chi tiết giao dịch'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              columns: [
                DataColumn(label: Text(tr('Mã GD'))),
                DataColumn(label: Text(tr('Thời gian'))),
                DataColumn(label: Text(tr('SL')), numeric: true),
                DataColumn(label: Text(tr('Doanh thu')), numeric: true),
                DataColumn(label: Text(tr('Thực thu')), numeric: true),
              ],
              rows: r.transactions
                  .map((t) => DataRow(cells: [
                        DataCell(Text(tr(t.orderNo))),
                        DataCell(Text(tr(_dt(t.createdAt)))),
                        DataCell(Text(tr(_qty(t.qty)))),
                        DataCell(Text(tr(_fmt(t.revenue)))),
                        DataCell(Text(tr(_fmt(t.actualReceived)))),
                      ]))
                  .toList(),
            ),
          ),
        ],
        if (_showProductDetail && r.products.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Hàng hóa bán ra'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...r.products.map((p) => _summaryLine(
                '',
                p.productName,
                '${_qty(p.qty)} · ${_fmt(p.revenue)}',
                indent: true,
              )),
        ],
      ],
    );
  }

  Widget _summaryLine(
    String idx,
    String label,
    String value, {
    bool indent = false,
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16 : 0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (idx.isNotEmpty)
            SizedBox(width: 22, child: Text(tr(idx), style: const TextStyle(fontSize: 12)))
          else if (!indent)
            const SizedBox(width: 22),
          Expanded(
            child: Text(
              tr(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            tr(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PosTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _presetChip('Hôm nay', PosKiotTimePreset.today),
                    _presetChip('Hôm qua', PosKiotTimePreset.yesterday),
                    _presetChip('7 ngày', PosKiotTimePreset.last7Days),
                    TextButton(
                      onPressed: _pickCustomRange,
                      child: Text(tr('Khác')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    value: _showProductDetail,
                    activeColor: _kiotBlue,
                    onChanged: _loading
                        ? null
                        : (v) async {
                            setState(() => _showProductDetail = v ?? true);
                            await _loadReport();
                          },
                  ),
                  Expanded(
                    child: Text(tr('Chi tiết hàng bán'), style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Thoát')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                    onPressed: _report == null || _loading ? null : _print,
                    icon: const Icon(Icons.print, size: 18),
                    label: Text(tr('In')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String label, PosKiotTimePreset preset) {
    final active = !_time.isCustom && _time.preset == preset;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: active ? _kiotBlue : PosTheme.textPrimary,
        backgroundColor: active ? PosTheme.kiotBlueLight : null,
      ),
      onPressed: _loading ? null : () => _applyPreset(preset),
      child: Text(tr(label), style: TextStyle(fontWeight: active ? FontWeight.w600 : null)),
    );
  }

  String _fmt(num v) => _money.format(v);
  String _qty(num v) => _qtyFmt.format(v);
  String _dt(DateTime d) => _dtFmt.format(d);
}
