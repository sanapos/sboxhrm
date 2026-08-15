import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../pos_reports_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hub 14 báo cáo tách riêng — dùng trên sidebar desktop / web.
class PosReportsHubScreen extends StatelessWidget {
  const PosReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final items = <({String label, IconData icon, String module, Widget screen})>[
      (label: 'Doanh thu', icon: Icons.trending_up, module: 'PosReportRevenue', screen: const PosRevenueReportScreen()),
      (label: 'Hàng hóa bán ra', icon: Icons.shopping_cart_outlined, module: 'PosReportSoldGoods', screen: const PosSoldGoodsReportScreen()),
      (label: 'Tồn kho', icon: Icons.warehouse_outlined, module: 'PosReportStock', screen: const PosReportsScreen(initialTab: 1, lockTab: true)),
      (label: 'Báo cáo nhập hàng', icon: Icons.move_to_inbox_outlined, module: 'PosReportPurchases', screen: const PosPurchaseReportScreen()),
      (label: 'Phương thức thanh toán', icon: Icons.payments_outlined, module: 'PosReportPayment', screen: const PosPaymentMethodReportScreen()),
      (label: 'Công nợ', icon: Icons.account_balance_outlined, module: 'PosReportDebt', screen: const PosDebtCombinedReportScreen()),
      (label: 'Hàng sắp hết hạn', icon: Icons.event_busy_outlined, module: 'PosReportExpiry', screen: const PosReportsScreen(initialTab: 2, lockTab: true)),
      (label: 'Lợi nhuận', icon: Icons.stacked_line_chart, module: 'PosReportProfit', screen: const PosProfitOnlyReportScreen()),
      (label: 'Chi phí', icon: Icons.money_off_outlined, module: 'PosReportExpense', screen: const PosExpenseReportScreen()),
      (label: 'Tổng kết cuối ngày', icon: Icons.nightlight_round, module: 'PosReportEndOfDay', screen: const PosEndOfDayScreen()),
      (label: 'Doanh thu theo nhân viên', icon: Icons.badge_outlined, module: 'PosReportStaffRevenue', screen: const PosStaffRevenueReportScreen()),
      (label: 'Sổ quỹ', icon: Icons.menu_book_outlined, module: 'PosReportCashbook', screen: const PosCashbookReportScreen()),
      (label: 'Kết quả kinh doanh', icon: Icons.account_balance, module: 'PosReportPnl', screen: const PosPnlReportScreen()),
      (label: 'Voucher', icon: Icons.confirmation_number_outlined, module: 'PosReportVoucher', screen: const PosVoucherUsageReportScreen()),
    ].where((item) => PermissionNavigation.canAccessModule(
          item.module,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          role: auth.user?.role,
        )).toList();
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Column(
        children: [
          const PosMobileKiotHeader(title: 'Báo cáo POS'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosMobileHubSectionGrid(
                  title: 'Báo cáo',
                  items: [
                    for (final item in items)
                      PosMobileHubGridItem(
                        label: item.label,
                        icon: item.icon,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PosHubScope(
                                embeddedInHub: false,
                                pushedSubPage: true,
                                child: item.screen,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _payColors = <Color>[
  PosTheme.kiotBlue,
  Color(0xFF0F766E),
  Color(0xFF7C3AED),
  Color(0xFFB45309),
  Color(0xFFBE123C),
  Color(0xFF475569),
];

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

List<Map<String, dynamic>> _maps(dynamic raw) => ((raw as List?) ?? [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

Widget _loadingBody() => ListView(
      children: const [
        SizedBox(
          height: 240,
          child: Center(
            child: CircularProgressIndicator(color: PosTheme.kiotBlue),
          ),
        ),
      ],
    );

String _fmtDt(dynamic v) {
  final dt = _parseDate(v);
  if (dt == null) return '';
  return DateFormat('dd/MM HH:mm').format(dt.toLocal());
}

/// Doanh thu — không gộp lợi nhuận / PTTT / nhân viên.
class PosRevenueReportScreen extends StatefulWidget {
  const PosRevenueReportScreen({super.key});

  @override
  State<PosRevenueReportScreen> createState() => _PosRevenueReportScreenState();
}

class _PosRevenueReportScreenState extends State<PosRevenueReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _data?['storeName']?.toString() ?? '';
    final revenue = _n(_data?['totalRevenue']);
    final vat = _n(_data?['totalVat']);
    final revenueInclVat = _n(_data?['totalRevenueInclVat']);
    final byDay = (_data?['byDay'] as List?) ?? [];
    final barPoints = byDay.whereType<Map>().map((d) {
      final dt = _parseDate(d['date']) ?? DateTime.now();
      return (date: dt, value: _n(d['total']));
    }).toList();

    return PosReportMobileScaffold(
      title: 'Doanh thu',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Doanh thu bán hàng',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportBarChart(points: barPoints),
                      const SizedBox(height: 12),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (label: 'DT chưa VAT', value: revenue, color: PosTheme.kiotBlue),
                          (label: 'VAT', value: vat, color: const Color(0xFF7C3AED)),
                          (
                            label: 'DT gồm VAT',
                            value: revenueInclVat > 0 ? revenueInclVat : revenue + vat,
                            color: const Color(0xFF0F766E),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Hoàn trả',
                            value: _n(_data?['totalRefund']),
                            color: Colors.orange.shade800,
                          ),
                          (
                            label: 'Đã thu',
                            value: _n(_data?['totalPaid']),
                            color: const Color(0xFF166534),
                          ),
                          (
                            label: 'Giảm giá',
                            value: _n(_data?['totalDiscount']),
                            color: Colors.grey.shade700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('${_n(_data?['orderCount']).toInt()} hóa đơn'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      PosReportBranchFooter(branchName: storeName),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Hàng hóa bán ra — top theo doanh thu, không gộp tồn kho.
class PosSoldGoodsReportScreen extends StatefulWidget {
  const PosSoldGoodsReportScreen({super.key});

  @override
  State<PosSoldGoodsReportScreen> createState() =>
      _PosSoldGoodsReportScreenState();
}

class _PosSoldGoodsReportScreenState extends State<PosSoldGoodsReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosGoodsReportSummary(
      from: _time.from,
      to: _time.to,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['topByRevenue']);
    return PosReportMobileScaffold(
      title: 'Hàng hóa bán ra',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Top hàng theo doanh thu',
                  child: PosReportRankList(
                    items: items,
                    labelOf: (p) {
                      final name = p['productName']?.toString() ??
                          p['name']?.toString() ??
                          '—';
                      final qty = _n(p['qty']);
                      return qty > 0
                          ? '$name · SL ${NumberFormat('#,##0.##', 'vi_VN').format(qty)}'
                          : name;
                    },
                    valueOf: (p) => _n(p['revenue']),
                    moneyFmt: _moneyFmt,
                    allowNegative: true,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Nhập hàng — phiếu nhập / trả NCC trong kỳ.
class PosPurchaseReportScreen extends StatefulWidget {
  const PosPurchaseReportScreen({super.key});

  @override
  State<PosPurchaseReportScreen> createState() => _PosPurchaseReportScreenState();
}

class _PosPurchaseReportScreenState extends State<PosPurchaseReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPurchasesReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final receipts = _maps(_data?['receipts']);
    final returns = _maps(_data?['returns']);
    return PosReportMobileScaffold(
      title: 'Báo cáo nhập hàng',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Tổng kỳ',
                  child: Column(
                    children: [
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Nhập',
                            value: _n(_data?['receiptAmount']),
                            color: PosTheme.kiotBlue,
                          ),
                          (
                            label: 'Trả NCC',
                            value: _n(_data?['returnAmount']),
                            color: Colors.orange.shade800,
                          ),
                          (
                            label: 'Đã trả tiền',
                            value: _n(_data?['paidInPeriod']),
                            color: const Color(0xFF166534),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('${_n(_data?['receiptCount']).toInt()} phiếu nhập · ${_n(_data?['returnCount']).toInt()} phiếu trả'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Phiếu nhập',
                  child: receipts.isEmpty
                      ? Text(tr('Chưa có dữ liệu'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(
                          children: [
                            for (var i = 0; i < receipts.length && i < 40; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _docRow(
                                receipts[i]['receiptNo']?.toString() ?? '—',
                                receipts[i]['supplierName']?.toString() ?? '',
                                receipts[i]['date'],
                                _n(receipts[i]['grandTotal']),
                              ),
                            ],
                          ],
                        ),
                ),
                PosReportCard(
                  title: 'Phiếu trả NCC',
                  child: returns.isEmpty
                      ? Text(tr('Chưa có dữ liệu'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(
                          children: [
                            for (var i = 0; i < returns.length && i < 40; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _docRow(
                                returns[i]['returnNo']?.toString() ?? '—',
                                returns[i]['supplierName']?.toString() ?? '',
                                returns[i]['date'],
                                _n(returns[i]['totalAmount']),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _docRow(String code, String name, dynamic date, double amount) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(code), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                tr([name, _fmtDt(date)].where((s) => s.isNotEmpty).join(' · ')),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
        Text(_moneyFmt.format(amount),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Phương thức thanh toán — không gộp doanh thu / lợi nhuận.
class PosPaymentMethodReportScreen extends StatefulWidget {
  const PosPaymentMethodReportScreen({super.key});

  @override
  State<PosPaymentMethodReportScreen> createState() =>
      _PosPaymentMethodReportScreenState();
}

class _PosPaymentMethodReportScreenState
    extends State<PosPaymentMethodReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _maps(_data?['byPayment']);
    final total = rows.fold<double>(0, (a, e) => a + _n(e['total']));
    final slices = <({String label, double value, Color color})>[];
    for (var i = 0; i < rows.length; i++) {
      slices.add((
        label: rows[i]['paymentMethod']?.toString() ?? 'Khác',
        value: _n(rows[i]['total']),
        color: _payColors[i % _payColors.length],
      ));
    }
    return PosReportMobileScaffold(
      title: 'Phương thức thanh toán',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Cơ cấu đã thu',
                  child: Column(
                    children: [
                      PosReportDonut(
                        total: total,
                        moneyFmt: _moneyFmt,
                        slices: slices,
                      ),
                      const SizedBox(height: 12),
                      PosReportRankList(
                        items: rows,
                        labelOf: (e) {
                          final name = e['paymentMethod']?.toString() ?? 'Khác';
                          final c = _n(e['count']).toInt();
                          return c > 0 ? '$name · $c giao dịch' : name;
                        },
                        valueOf: (e) => _n(e['total']),
                        moneyFmt: _moneyFmt,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Công nợ khách + nhà cung cấp.
class PosDebtCombinedReportScreen extends StatefulWidget {
  const PosDebtCombinedReportScreen({super.key});

  @override
  State<PosDebtCombinedReportScreen> createState() =>
      _PosDebtCombinedReportScreenState();
}

class _PosDebtCombinedReportScreenState
    extends State<PosDebtCombinedReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  bool _loading = true;
  Map<String, dynamic>? _customers;
  Map<String, dynamic>? _suppliers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getPosCustomerDebtReport(),
      _api.getPosSupplierDebtReport(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _customers = results[0]['isSuccess'] == true && results[0]['data'] is Map
          ? Map<String, dynamic>.from(results[0]['data'] as Map)
          : null;
      _suppliers = results[1]['isSuccess'] == true && results[1]['data'] is Map
          ? Map<String, dynamic>.from(results[1]['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kh = _maps(_customers?['items']);
    final ncc = _maps(_suppliers?['items']);
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Column(
        children: [
          const PosMobileKiotHeader(title: 'Báo cáo công nợ'),
          Expanded(
            child: RefreshIndicator(
              color: PosTheme.kiotBlue,
              onRefresh: _load,
              child: _loading
                  ? _loadingBody()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        PosReportCard(
                          title: 'Công nợ khách hàng',
                          child: Column(
                            children: [
                              PosReportMetricTiles(
                                moneyFmt: _moneyFmt,
                                tiles: [
                                  (
                                    label: 'Tổng nợ',
                                    value: _n(_customers?['sumDebt']),
                                    color: Colors.red.shade700,
                                  ),
                                  (
                                    label: '0–30 ngày',
                                    value: _n(_customers?['sumDebt0To30']),
                                    color: PosTheme.kiotBlue,
                                  ),
                                  (
                                    label: '>90 ngày',
                                    value: _n(_customers?['sumDebtOver90']),
                                    color: Colors.orange.shade800,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PosReportRankList(
                                items: kh.take(30).toList(),
                                labelOf: (e) =>
                                    e['name']?.toString() ??
                                    e['customerName']?.toString() ??
                                    '—',
                                valueOf: (e) => _n(e['currentDebt'] ?? e['debt']),
                                moneyFmt: _moneyFmt,
                              ),
                            ],
                          ),
                        ),
                        PosReportCard(
                          title: 'Công nợ nhà cung cấp',
                          child: Column(
                            children: [
                              PosReportMetricTiles(
                                moneyFmt: _moneyFmt,
                                tiles: [
                                  (
                                    label: 'Tổng nợ',
                                    value: _n(_suppliers?['sumDebt']),
                                    color: Colors.red.shade700,
                                  ),
                                  (
                                    label: 'NCC',
                                    value: _n(_suppliers?['totalSuppliers']),
                                    color: PosTheme.kiotBlue,
                                  ),
                                  (
                                    label: '>90 ngày',
                                    value: _n(_suppliers?['sumDebtOver90']),
                                    color: Colors.orange.shade800,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PosReportRankList(
                                items: ncc.take(30).toList(),
                                labelOf: (e) => e['name']?.toString() ?? '—',
                                valueOf: (e) => _n(e['currentDebt']),
                                moneyFmt: _moneyFmt,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lợi nhuận gộp — không gộp PTTT / nhân viên / HĐĐT.
class PosProfitOnlyReportScreen extends StatefulWidget {
  const PosProfitOnlyReportScreen({super.key});

  @override
  State<PosProfitOnlyReportScreen> createState() =>
      _PosProfitOnlyReportScreenState();
}

class _PosProfitOnlyReportScreenState extends State<PosProfitOnlyReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final revenue = _n(_data?['totalRevenue']);
    final cogs = _n(_data?['totalCogs']);
    final profit = _n(_data?['totalProfit']);
    final margin = _n(_data?['profitMarginPct']);
    final profitByDay = (_data?['profitByDay'] as List?) ?? [];
    final linePoints = profitByDay.whereType<Map>().map((d) {
      final dt = _parseDate(d['date']) ?? DateTime.now();
      return (
        date: dt,
        revenue: _n(d['revenue']),
        cogs: _n(d['cogs']),
        profit: _n(d['profit']),
      );
    }).toList();

    return PosReportMobileScaffold(
      title: 'Báo cáo lợi nhuận',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Lợi nhuận gộp',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportMultiLineChart(points: linePoints),
                      const SizedBox(height: 12),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (label: 'Lợi nhuận', value: profit, color: const Color(0xFF166534)),
                          (label: 'Doanh thu', value: revenue, color: PosTheme.kiotBlue),
                          (label: 'Giá vốn', value: cogs, color: Colors.amber.shade700),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Biên LN: ${margin.toStringAsFixed(1)}%'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Chi phí từ sổ quỹ (phiếu chi).
class PosExpenseReportScreen extends StatefulWidget {
  const PosExpenseReportScreen({super.key});

  @override
  State<PosExpenseReportScreen> createState() => _PosExpenseReportScreenState();
}

class _PosExpenseReportScreenState extends State<PosExpenseReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosExpenseReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = _maps(_data?['byCategory']);
    final items = _maps(_data?['items']);
    return PosReportMobileScaffold(
      title: 'Báo cáo chi phí',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Tổng chi',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Tổng chi',
                            value: _n(_data?['total']),
                            color: Colors.red.shade700,
                          ),
                          (
                            label: 'Số phiếu',
                            value: _n(_data?['count']),
                            color: PosTheme.kiotBlue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PosReportRankList(
                        items: cats,
                        labelOf: (e) => e['category']?.toString() ?? 'Khác',
                        valueOf: (e) => _n(e['total']),
                        moneyFmt: _moneyFmt,
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Phiếu chi gần đây',
                  child: items.isEmpty
                      ? Text(tr('Chưa có dữ liệu'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _txRow(
                                items[i]['transactionCode']?.toString() ??
                                    items[i]['category']?.toString() ??
                                    'Chi',
                                items[i]['description']?.toString() ??
                                    items[i]['category']?.toString() ??
                                    '',
                                items[i]['transactionDate'],
                                _n(items[i]['amount']),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _txRow(String code, String note, dynamic date, double amount) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(code), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                tr([note, _fmtDt(date)].where((s) => s.isNotEmpty).join(' · ')),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
        Text(_moneyFmt.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            )),
      ],
    );
  }
}

/// Doanh thu theo nhân viên.
class PosStaffRevenueReportScreen extends StatefulWidget {
  const PosStaffRevenueReportScreen({super.key});

  @override
  State<PosStaffRevenueReportScreen> createState() =>
      _PosStaffRevenueReportScreenState();
}

class _PosStaffRevenueReportScreenState
    extends State<PosStaffRevenueReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final staff = _maps(_data?['topEmployees']);
    return PosReportMobileScaffold(
      title: 'Doanh thu theo nhân viên',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Theo người bán',
                  child: PosReportRankList(
                    items: staff,
                    labelOf: (e) {
                      final name = e['soldBy']?.toString().trim().isNotEmpty == true
                          ? e['soldBy'].toString()
                          : '—';
                      final c = _n(e['orderCount']).toInt();
                      return c > 0 ? '$name · $c HĐ' : name;
                    },
                    valueOf: (e) => _n(e['revenue']),
                    moneyFmt: _moneyFmt,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Sổ quỹ — thu / chi / tồn kỳ.
class PosCashbookReportScreen extends StatefulWidget {
  const PosCashbookReportScreen({super.key});

  @override
  State<PosCashbookReportScreen> createState() => _PosCashbookReportScreenState();
}

class _PosCashbookReportScreenState extends State<PosCashbookReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCashbookReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['items']);
    return PosReportMobileScaffold(
      title: 'Sổ quỹ',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Thu — chi kỳ',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Thu',
                        value: _n(_data?['income']),
                        color: const Color(0xFF166534),
                      ),
                      (
                        label: 'Chi',
                        value: _n(_data?['expense']),
                        color: Colors.red.shade700,
                      ),
                      (
                        label: 'Chênh lệch',
                        value: _n(_data?['net']),
                        color: PosTheme.kiotBlue,
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Giao dịch gần đây',
                  child: items.isEmpty
                      ? Text(tr('Chưa có dữ liệu'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _cashRow(items[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _cashRow(Map<String, dynamic> e) {
    final income = e['type']?.toString().toLowerCase() == 'income';
    final amount = _n(e['amount']);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(e['transactionCode']?.toString() ??
                    e['category']?.toString() ??
                    (income ? 'Thu' : 'Chi')),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                tr([
                  e['description']?.toString() ?? '',
                  e['paymentMethod']?.toString() ?? '',
                  _fmtDt(e['transactionDate']),
                ].where((s) => s.isNotEmpty).join(' · ')),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '${income ? '+' : '-'}${_moneyFmt.format(amount)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: income ? const Color(0xFF166534) : Colors.red.shade700,
          ),
        ),
      ],
    );
  }
}

/// Kết quả kinh doanh (P&L).
class PosPnlReportScreen extends StatefulWidget {
  const PosPnlReportScreen({super.key});

  @override
  State<PosPnlReportScreen> createState() => _PosPnlReportScreenState();
}

class _PosPnlReportScreenState extends State<PosPnlReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPnlReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = _n(_data?['netProfit']);
    return PosReportMobileScaffold(
      title: 'Kết quả kinh doanh',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'P&L kỳ',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Doanh thu',
                            value: _n(_data?['revenue']),
                            color: PosTheme.kiotBlue,
                          ),
                          (
                            label: 'VAT',
                            value: _n(_data?['vat']),
                            color: const Color(0xFF7C3AED),
                          ),
                          (
                            label: 'Giảm giá',
                            value: _n(_data?['discount']),
                            color: Colors.grey.shade700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Giá vốn',
                            value: _n(_data?['cogs']),
                            color: Colors.amber.shade700,
                          ),
                          (
                            label: 'LN gộp',
                            value: _n(_data?['grossProfit']),
                            color: const Color(0xFF0F766E),
                          ),
                          (
                            label: 'Chi phí',
                            value: _n(_data?['expenses']),
                            color: Colors.red.shade700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('LN ròng: ${_moneyFmt.format(net)}  ·  biên ${_n(_data?['marginPct']).toStringAsFixed(1)}%  ·  ${_n(_data?['orderCount']).toInt()} HĐ'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: net < 0 ? Colors.red.shade700 : const Color(0xFF166534),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Voucher đã dùng trên hóa đơn — không phải màn CRUD.
class PosVoucherUsageReportScreen extends StatefulWidget {
  const PosVoucherUsageReportScreen({super.key});

  @override
  State<PosVoucherUsageReportScreen> createState() =>
      _PosVoucherUsageReportScreenState();
}

class _PosVoucherUsageReportScreenState
    extends State<PosVoucherUsageReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosVoucherReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['items']);
    return PosReportMobileScaffold(
      title: 'Báo cáo voucher',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Sử dụng voucher',
                  child: Column(
                    children: [
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Giảm giá',
                            value: _n(_data?['totalDiscount']),
                            color: Colors.orange.shade800,
                          ),
                          (
                            label: 'DT kèm VC',
                            value: _n(_data?['revenueWithVoucher']),
                            color: PosTheme.kiotBlue,
                          ),
                          (
                            label: 'Lượt dùng',
                            value: _n(_data?['uses']),
                            color: const Color(0xFF166534),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PosReportRankList(
                        items: items,
                        labelOf: (e) {
                          final code = e['voucherCode']?.toString() ?? '—';
                          final uses = _n(e['uses']).toInt();
                          return uses > 0 ? '$code · $uses lượt' : code;
                        },
                        valueOf: (e) => _n(e['discount']),
                        moneyFmt: _moneyFmt,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
