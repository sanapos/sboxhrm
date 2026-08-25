import 'dart:async';

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
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/reports/pos_goods_filter_sheet.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../pos_reports_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Hub 14 báo cáo — cùng token trang chủ A7 (nền xám, thẻ nổi, chữ #2B3437).
class PosReportsHubScreen extends StatelessWidget {
  const PosReportsHubScreen({super.key});

  static const _pageBg = Color(0xFFF1F4F6);
  static const _ink = Color(0xFF2B3437);
  static const _muted = Color(0xFF586064);
  static const _hint = Color(0xFF8A9199);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final items = <({
      String label,
      String subtitle,
      IconData icon,
      String module,
      Widget screen
    })>[
      (label: 'Doanh thu', subtitle: 'Theo ngày', icon: Icons.trending_up, module: 'PosReportRevenue', screen: const PosRevenueReportScreen()),
      (label: 'Hàng hóa bán ra', subtitle: 'Mặt hàng', icon: Icons.shopping_cart_outlined, module: 'PosReportSoldGoods', screen: const PosSoldGoodsReportScreen()),
      (label: 'Tồn kho', subtitle: 'Kho hàng', icon: Icons.warehouse_outlined, module: 'PosReportStock', screen: const PosReportsScreen(initialTab: 1, lockTab: true)),
      (label: 'Báo cáo nhập hàng', subtitle: 'Phiếu nhập', icon: Icons.move_to_inbox_outlined, module: 'PosReportPurchases', screen: const PosPurchaseReportScreen()),
      (label: 'Phương thức thanh toán', subtitle: 'PTTT', icon: Icons.payments_outlined, module: 'PosReportPayment', screen: const PosPaymentMethodReportScreen()),
      (label: 'Công nợ', subtitle: 'Phải thu / trả', icon: Icons.account_balance_outlined, module: 'PosReportDebt', screen: const PosDebtCombinedReportScreen()),
      (label: 'Hàng sắp hết hạn', subtitle: 'Lô / HSD', icon: Icons.event_busy_outlined, module: 'PosReportExpiry', screen: const PosReportsScreen(initialTab: 2, lockTab: true)),
      (label: 'Lợi nhuận', subtitle: 'Lãi gộp', icon: Icons.stacked_line_chart, module: 'PosReportProfit', screen: const PosProfitOnlyReportScreen()),
      (label: 'Chi phí', subtitle: 'Thu / chi', icon: Icons.money_off_outlined, module: 'PosReportExpense', screen: const PosExpenseReportScreen()),
      (label: 'Tổng kết cuối ngày', subtitle: 'Cuối ngày', icon: Icons.nightlight_round, module: 'PosReportEndOfDay', screen: const PosEndOfDayScreen()),
      (label: 'Doanh thu theo nhân viên', subtitle: 'Thu ngân', icon: Icons.badge_outlined, module: 'PosReportStaffRevenue', screen: const PosStaffRevenueReportScreen()),
      (label: 'Sổ quỹ', subtitle: 'Tiền mặt', icon: Icons.menu_book_outlined, module: 'PosReportCashbook', screen: const PosCashbookReportScreen()),
      (label: 'Kết quả kinh doanh', subtitle: 'P&L', icon: Icons.account_balance, module: 'PosReportPnl', screen: const PosPnlReportScreen()),
      (label: 'Voucher', subtitle: 'Sử dụng', icon: Icons.confirmation_number_outlined, module: 'PosReportVoucher', screen: const PosVoucherUsageReportScreen()),
    ].where((item) => PermissionNavigation.canAccessModule(
          item.module,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          role: auth.user?.role,
        )).toList();
    final header = Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        height: 56,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
        ),
        child: Row(
          children: [
            if (Navigator.of(context).canPop())
              IconButton(
                icon: const Icon(Icons.arrow_back, color: _ink, size: 22),
                onPressed: () => Navigator.maybePop(context),
              ),
            Expanded(
              child: Text(
                tr('Báo cáo POS'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: _pageBg,
      child: Column(
        children: [
          posNeedsTopSafeArea(context)
              ? SafeArea(bottom: false, child: header)
              : header,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                _PosReportsHubSection(items: items),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosReportsHubSection extends StatelessWidget {
  const _PosReportsHubSection({required this.items});

  final List<
      ({
        String label,
        String subtitle,
        IconData icon,
        String module,
        Widget screen
      })> items;

  @override
  Widget build(BuildContext context) {
    const color = PosTheme.kiotBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.72)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.assessment, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Báo cáo'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PosReportsHubScreen._ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('Phân tích số liệu'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: PosReportsHubScreen._muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 1100 ? 3 : (w >= 640 ? 2 : 1);
            final gap = 12.0;
            if (cols == 1) {
              return Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PosReportHubCard(item: item),
                    ),
                ],
              );
            }
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: (w - (cols - 1) * gap) / cols,
                    child: _PosReportHubCard(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PosReportHubCard extends StatelessWidget {
  const _PosReportHubCard({required this.item});

  final ({
    String label,
    String subtitle,
    IconData icon,
    String module,
    Widget screen
  }) item;

  @override
  Widget build(BuildContext context) {
    const color = PosTheme.kiotBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: color.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.16),
                      color.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(item.label),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PosReportsHubScreen._ink,
                        letterSpacing: -0.15,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(item.subtitle),
                      style: const TextStyle(
                        fontSize: 12,
                        color: PosReportsHubScreen._hint,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFFB0B7BD),
              ),
            ],
          ),
        ),
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
  final _pngKey = GlobalKey();
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

  Future<void> _exportExcel() async {
    final d = _data;
    if (d == null) return;
    final byDay = _maps(d['byDay']);
    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo doanh thu',
      sheetName: 'Doanh thu',
      filePrefix: 'POS_DoanhThu',
      periodLabel: _time.displayLabel,
      headers: const ['Hạng mục', 'Giá trị'],
      rows: [
        ['DT chưa VAT', _n(d['totalRevenue'])],
        ['VAT', _n(d['totalVat'])],
        ['DT gồm VAT', _n(d['totalRevenueInclVat'])],
        ['Hoàn trả', _n(d['totalRefund'])],
        ['Đã thu', _n(d['totalPaid'])],
        ['Giảm giá', _n(d['totalDiscount'])],
        ['Số hóa đơn', _n(d['orderCount']).toInt()],
        for (final e in byDay)
          [_fmtDt(e['date']), _n(e['total'])],
      ],
      summaryLines: ['Cửa hàng: ${d['storeName'] ?? ''}'],
    );
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(_exportExcel()),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_DoanhThu',
      )),
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
                        onTileTap: (_) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                        ),
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
                        onTileTap: (_) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                        ),
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
                      InkWell(
                        onTap: () => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                        ),
                        child: Text(
                          tr('${_n(_data?['orderCount']).toInt()} hóa đơn · xem chi tiết'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PosTheme.kiotBlue,
                          ),
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
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  PosGoodsReportFilter _filter = const PosGoodsReportFilter();
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
      includeGoods: _filter.includeGoods,
      includeService: _filter.includeService,
      includeCombo: _filter.includeCombo,
      activeOnly: _filter.activeOnly,
      inactiveOnly: _filter.inactiveOnly,
      inventoryStatus: _filter.inventoryStatus == PosGoodsInventoryFilter.all
          ? null
          : _filter.inventoryStatus.name,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  Future<void> _openFilter() async {
    final picked = await showModalBottomSheet<PosGoodsReportFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PosGoodsFilterSheet(initial: _filter),
    );
    if (picked == null) return;
    setState(() => _filter = picked);
    await _load();
  }

  Future<void> _exportExcel() async {
    final items = _maps(_data?['topByRevenue']);
    await PosReportExport.excel(
      context: context,
      title: 'Hàng hóa bán ra',
      sheetName: 'Hang hoa',
      filePrefix: 'POS_HangHoaBanRa',
      periodLabel: _time.displayLabel,
      headers: const ['Hàng hóa', 'SL', 'Doanh thu'],
      rows: [
        for (final p in items)
          [
            p['productName'] ?? p['name'] ?? '',
            _n(p['qty']),
            _n(p['revenue']),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['topByRevenue']);
    return PosReportMobileScaffold(
      title: 'Hàng hóa bán ra',
      time: _time,
      pngKey: _pngKey,
      onFilterTap: () => unawaited(_openFilter()),
      onExportExcel: () => unawaited(_exportExcel()),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_HangHoaBanRa',
      )),
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
                    onItemTap: (p) => PosReportOpen.product(
                      context,
                      id: '${p['productId'] ?? p['id'] ?? ''}',
                      name: p['productName']?.toString() ?? p['name']?.toString(),
                      from: _time.from,
                      to: _time.to,
                    ),
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
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  int _docKind = 0;
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

  Future<void> _exportExcel(
    List<Map<String, dynamic>> receipts,
    List<Map<String, dynamic>> returns,
  ) async {
    final rows = <List<dynamic>>[
      if (_docKind != 2)
        for (final e in receipts)
          [
            'Nhập',
            e['receiptNo'] ?? '',
            e['supplierName'] ?? '',
            _fmtDt(e['date']),
            _n(e['grandTotal']),
          ],
      if (_docKind != 1)
        for (final e in returns)
          [
            'Trả NCC',
            e['returnNo'] ?? '',
            e['supplierName'] ?? '',
            _fmtDt(e['date']),
            _n(e['totalAmount']),
          ],
    ];
    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo nhập hàng',
      sheetName: 'Nhap hang',
      filePrefix: 'POS_NhapHang',
      periodLabel: _time.displayLabel,
      filterLabel: const ['Tất cả', 'Phiếu nhập', 'Trả NCC'][_docKind],
      headers: const ['Loại', 'Số phiếu', 'NCC', 'Ngày', 'Số tiền'],
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final receipts = _maps(_data?['receipts']);
    final returns = _maps(_data?['returns']);
    return PosReportMobileScaffold(
      title: 'Báo cáo nhập hàng',
      time: _time,
      pngKey: _pngKey,
      filterBar: PosReportChipBar(
        labels: const ['Tất cả', 'Phiếu nhập', 'Trả NCC'],
        selected: _docKind,
        onSelected: (i) => setState(() => _docKind = i),
      ),
      onExportExcel: () => unawaited(_exportExcel(receipts, returns)),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_NhapHang',
      )),
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
                if (_docKind != 2)
                PosReportCard(
                  title: 'Phiếu nhập',
                  child: receipts.isEmpty
                      ? const PosReportEmpty()
                      : Column(
                          children: [
                            for (var i = 0; i < receipts.length && i < 40; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _docRow(
                                receipts[i]['receiptNo']?.toString() ?? '—',
                                receipts[i]['supplierName']?.toString() ?? '',
                                receipts[i]['date'],
                                _n(receipts[i]['grandTotal']),
                                onTap: () => PosReportOpen.purchaseReceipt(
                                  context,
                                  '${receipts[i]['id'] ?? ''}',
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (_docKind != 1)
                PosReportCard(
                  title: 'Phiếu trả NCC',
                  child: returns.isEmpty
                      ? const PosReportEmpty()
                      : Column(
                          children: [
                            for (var i = 0; i < returns.length && i < 40; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _docRow(
                                returns[i]['returnNo']?.toString() ?? '—',
                                returns[i]['supplierName']?.toString() ?? '',
                                returns[i]['date'],
                                _n(returns[i]['totalAmount']),
                                onTap: () => PosReportOpen.purchaseReturn(
                                  context,
                                  '${returns[i]['id'] ?? ''}',
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _docRow(
    String code,
    String name,
    dynamic date,
    double amount, {
    VoidCallback? onTap,
  }) {
    return PosReportNavRow(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B3437),
                  ),
                ),
                Text(
                  tr([name, _fmtDt(date)].where((s) => s.isNotEmpty).join(' · ')),
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                ),
              ],
            ),
          ),
          PosReportMoneyLabel(amount, color: const Color(0xFF2B3437)),
        ],
      ),
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
  final _pngKey = GlobalKey();
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Phương thức thanh toán',
        sheetName: 'PTTT',
        filePrefix: 'POS_PTTT',
        periodLabel: _time.displayLabel,
        headers: const ['Phương thức', 'Số GD', 'Tổng'],
        rows: [
          for (final e in rows)
            [
              e['paymentMethod'] ?? 'Khác',
              _n(e['count']).toInt(),
              _n(e['total']),
            ],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_PTTT',
      )),
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
                        onItemTap: (e) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                          paymentMethod: e['paymentMethod']?.toString(),
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
  final _pngKey = GlobalKey();
  final _searchCtrl = TextEditingController();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  int _party = 0;
  bool _includeZero = false;
  bool _loading = true;
  Map<String, dynamic>? _customers;
  Map<String, dynamic>? _suppliers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _searchCtrl.text.trim();
    final results = await Future.wait([
      _api.getPosCustomerDebtReport(
        search: q.isEmpty ? null : q,
        includeZeroDebt: _includeZero,
      ),
      _api.getPosSupplierDebtReport(
        search: q.isEmpty ? null : q,
        includeZeroDebt: _includeZero,
      ),
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
    return PosReportMobileScaffold(
      title: 'Báo cáo công nợ',
      time: _time,
      showTimeFilter: false,
      pngKey: _pngKey,
      onTimeChanged: (_) {},
      onRefresh: _load,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo công nợ',
        sheetName: 'Cong no',
        filePrefix: 'POS_CongNo',
        filterLabel: [
          'Tất cả',
          'Khách hàng',
          'NCC',
        ][_party] +
            (_includeZero ? ' · gồm dư 0' : ''),
        headers: const ['Loại', 'Tên', 'Công nợ'],
        rows: [
          if (_party != 2)
            for (final e in kh)
              [
                'KH',
                e['name'] ?? e['customerName'] ?? '',
                _n(e['currentDebt'] ?? e['debt']),
              ],
          if (_party != 1)
            for (final e in ncc)
              [
                'NCC',
                e['name'] ?? '',
                _n(e['currentDebt']),
              ],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_CongNo',
      )),
      filterBar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: tr('Tìm khách / NCC'),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 8),
          PosReportChipBar(
            labels: const ['Tất cả', 'Khách hàng', 'NCC'],
            selected: _party,
            onSelected: (i) => setState(() => _party = i),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: Text(tr('Gồm dư 0')),
              selected: _includeZero,
              onSelected: (v) {
                setState(() => _includeZero = v);
                _load();
              },
            ),
          ),
        ],
      ),
      body: _loading
          ? _loadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (_party != 2)
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
                          onItemTap: (e) => PosReportOpen.sales(
                            context,
                            customerId: '${e['id'] ?? ''}',
                            customerName: e['name']?.toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_party != 1)
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
                          onItemTap: (e) => PosReportOpen.purchases(
                            context,
                            search: e['name']?.toString() ??
                                e['supplierCode']?.toString(),
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
  final _pngKey = GlobalKey();
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo lợi nhuận',
        sheetName: 'Loi nhuan',
        filePrefix: 'POS_LoiNhuan',
        periodLabel: _time.displayLabel,
        headers: const ['Chỉ tiêu', 'Giá trị'],
        rows: [
          ['Doanh thu', revenue],
          ['Giá vốn', cogs],
          ['Lợi nhuận', profit],
          ['Biên LN %', margin],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_LoiNhuan',
      )),
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
                        onTileTap: (_) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                        ),
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
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  String? _category;
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
    final items = _maps(_data?['items'])
        .where((e) =>
            _category == null || e['category']?.toString() == _category)
        .toList();
    final catLabels = [
      'Tất cả',
      ...cats.map((e) => e['category']?.toString() ?? 'Khác'),
    ];
    final catSelected = _category == null
        ? 0
        : catLabels.indexWhere((l) => l == _category).clamp(0, catLabels.length - 1);
    return PosReportMobileScaffold(
      title: 'Báo cáo chi phí',
      time: _time,
      pngKey: _pngKey,
      filterBar: catLabels.length > 1
          ? PosReportChipBar(
              labels: catLabels.take(8).toList(),
              selected: catSelected,
              onSelected: (i) => setState(() {
                _category = i == 0 ? null : catLabels[i];
              }),
            )
          : null,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo chi phí',
        sheetName: 'Chi phi',
        filePrefix: 'POS_ChiPhi',
        periodLabel: _time.displayLabel,
        filterLabel: _category,
        headers: const ['Mã', 'Danh mục', 'Ngày', 'Số tiền'],
        rows: [
          for (final e in items)
            [
              e['transactionCode'] ?? '',
              e['category'] ?? '',
              _fmtDt(e['transactionDate']),
              _n(e['amount']),
            ],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_ChiPhi',
      )),
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
                      ? const PosReportEmpty()
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 14),
                              _txRow(items[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _txRow(Map<String, dynamic> e) {
    final code = e['transactionCode']?.toString() ??
        e['category']?.toString() ??
        'Chi';
    final note = e['description']?.toString() ?? e['category']?.toString() ?? '';
    final amount = _n(e['amount']);
    return PosReportNavRow(
      onTap: () => PosReportOpen.cashTx(context, e),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B3437),
                  ),
                ),
                Text(
                  tr([note, _fmtDt(e['transactionDate'])]
                      .where((s) => s.isNotEmpty)
                      .join(' · ')),
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                ),
              ],
            ),
          ),
          PosReportMoneyLabel(amount, color: const Color(0xFFB42318)),
        ],
      ),
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
  final _pngKey = GlobalKey();
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Doanh thu theo nhân viên',
        sheetName: 'Nhan vien',
        filePrefix: 'POS_DTNhanVien',
        periodLabel: _time.displayLabel,
        headers: const ['Nhân viên', 'Số HĐ', 'Doanh thu'],
        rows: [
          for (final e in staff)
            [
              e['soldBy'] ?? '',
              _n(e['orderCount']).toInt(),
              _n(e['revenue']),
            ],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_DTNhanVien',
      )),
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
                    onItemTap: (e) => PosReportOpen.sales(
                      context,
                      from: _time.from,
                      to: _time.to,
                      soldBy: e['soldBy']?.toString(),
                    ),
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
  final _pngKey = GlobalKey();
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  int _cashKind = 0;
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
    final items = _maps(_data?['items']).where((e) {
      if (_cashKind == 0) return true;
      final income = e['type']?.toString().toLowerCase() == 'income';
      return _cashKind == 1 ? income : !income;
    }).toList();
    return PosReportMobileScaffold(
      title: 'Sổ quỹ',
      time: _time,
      pngKey: _pngKey,
      filterBar: PosReportChipBar(
        labels: const ['Tất cả', 'Thu', 'Chi'],
        selected: _cashKind,
        onSelected: (i) => setState(() => _cashKind = i),
      ),
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Sổ quỹ',
        sheetName: 'So quy',
        filePrefix: 'POS_SoQuy',
        periodLabel: _time.displayLabel,
        filterLabel: const ['Tất cả', 'Thu', 'Chi'][_cashKind],
        headers: const ['Mã', 'Loại', 'Danh mục', 'Ngày', 'Số tiền'],
        rows: [
          for (final e in items)
            [
              e['transactionCode'] ?? '',
              e['type'] ?? '',
              e['category'] ?? '',
              _fmtDt(e['transactionDate']),
              _n(e['amount']),
            ],
        ],
        summaryLines: [
          'Thu: ${_moneyFmt.format(_n(_data?['income']))}',
          'Chi: ${_moneyFmt.format(_n(_data?['expense']))}',
          'Chênh lệch: ${_moneyFmt.format(_n(_data?['net']))}',
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_SoQuy',
      )),
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
                      ? const PosReportEmpty()
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
    return PosReportNavRow(
      onTap: () => PosReportOpen.cashTx(context, e),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e['transactionCode']?.toString() ??
                      e['category']?.toString() ??
                      (income ? 'Thu' : 'Chi'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B3437),
                  ),
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
          PosReportMoneyLabel(
            amount,
            prefix: income ? '+' : '-',
            color: income ? const Color(0xFF166534) : const Color(0xFFB42318),
          ),
        ],
      ),
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
  final _pngKey = GlobalKey();
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Kết quả kinh doanh',
        sheetName: 'P&L',
        filePrefix: 'POS_KQKD',
        periodLabel: _time.displayLabel,
        headers: const ['Chỉ tiêu', 'Giá trị'],
        rows: [
          ['Doanh thu', _n(_data?['revenue'])],
          ['VAT', _n(_data?['vat'])],
          ['Giảm giá', _n(_data?['discount'])],
          ['Giá vốn', _n(_data?['cogs'])],
          ['LN gộp', _n(_data?['grossProfit'])],
          ['Chi phí', _n(_data?['expenses'])],
          ['LN ròng', net],
          ['Biên %', _n(_data?['marginPct'])],
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_KQKD',
      )),
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
                        onTileTap: (_) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                        ),
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
                        tr('LN ròng: ${posReportMoney(net)}  ·  biên ${_n(_data?['marginPct']).toStringAsFixed(1)}%  ·  ${_n(_data?['orderCount']).toInt()} HĐ'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: net < 0
                              ? const Color(0xFFB42318)
                              : const Color(0xFF166534),
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
  final _pngKey = GlobalKey();
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
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo voucher',
        sheetName: 'Voucher',
        filePrefix: 'POS_Voucher',
        periodLabel: _time.displayLabel,
        headers: const ['Mã', 'Lượt dùng', 'Giảm giá'],
        rows: [
          for (final e in items)
            [
              e['voucherCode'] ?? '',
              _n(e['uses']).toInt(),
              _n(e['discount']),
            ],
        ],
        summaryLines: [
          'Tổng giảm: ${_moneyFmt.format(_n(_data?['totalDiscount']))}',
          'DT kèm VC: ${_moneyFmt.format(_n(_data?['revenueWithVoucher']))}',
        ],
      )),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_Voucher',
      )),
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
                        onItemTap: (e) => PosReportOpen.sales(
                          context,
                          from: _time.from,
                          to: _time.to,
                          search: e['voucherCode']?.toString(),
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
