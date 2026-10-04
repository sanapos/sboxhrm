import 'dart:async';

import 'package:flutter/material.dart';
import '../../utils/api_datetime.dart';
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
import '../analytics_reports_screen.dart';
import '../pos_reports_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_einvoice_report_screen.dart';
import 'pos_profit_report_screen.dart';
import 'pos_customer_sales_report_screen.dart';
import 'pos_stock_health_report_screen.dart';
import 'pos_hkd_books_screen.dart';
import 'pos_staff_commission_report_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_shipping_report_screen.dart';
import '../../widgets/sbox/sbox_ui.dart';
/// Hub 14 báo cáo — cùng token trang chủ A7 (nền xám, thẻ nổi, chữ #2B3437).
class PosReportsHubScreen extends StatelessWidget {
  const PosReportsHubScreen({super.key});

  static const _pageBg = Color(0xFFF1F4F6);
  static const _ink = Color(0xFF2B3437);
  static const _muted = SboxColors.slate600;
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
      (label: 'Lợi nhuận', subtitle: 'Theo hàng / nhóm / kênh / NV', icon: Icons.stacked_line_chart, module: 'PosReportProfit', screen: const PosProfitReportScreen()),
      (label: 'Chi phí', subtitle: 'Thu / chi', icon: Icons.money_off_outlined, module: 'PosReportExpense', screen: const PosExpenseReportScreen()),
      (label: 'Tổng kết cuối ngày', subtitle: 'Cuối ngày', icon: Icons.nightlight_round, module: 'PosReportEndOfDay', screen: const PosEndOfDayScreen()),
      (label: 'Doanh thu theo nhân viên', subtitle: 'Thu ngân', icon: Icons.badge_outlined, module: 'PosReportStaffRevenue', screen: const PosStaffRevenueReportScreen()),
      (label: 'Hoa hồng nhân viên', subtitle: 'DV / combo', icon: Icons.handshake_outlined, module: 'PosReportStaffCommission', screen: const PosStaffCommissionReportScreen()),
      (label: 'Vận chuyển', subtitle: 'Hãng / thất bại / hoàn / COD', icon: Icons.local_shipping_outlined, module: 'PosShipping', screen: const PosShippingReportScreen()),
      (label: 'Sổ quỹ', subtitle: 'Tiền mặt', icon: Icons.menu_book_outlined, module: 'PosReportCashbook', screen: const PosCashbookReportScreen()),
      (label: 'Kết quả kinh doanh', subtitle: 'P&L', icon: Icons.account_balance, module: 'PosReportPnl', screen: const PosPnlReportScreen()),
      (label: 'Voucher', subtitle: 'Sử dụng', icon: Icons.confirmation_number_outlined, module: 'PosReportVoucher', screen: const PosVoucherUsageReportScreen()),
      (label: 'Bán theo khách', subtitle: 'Doanh thu / nợ KH', icon: Icons.people_outline, module: 'PosReportRevenue', screen: const PosCustomerSalesReportScreen()),
      (label: 'Sức khỏe kho', subtitle: 'Cháy / chậm / chết tồn', icon: Icons.inventory_2_outlined, module: 'PosReportStock', screen: const PosStockHealthReportScreen()),
      (label: 'Hóa đơn điện tử', subtitle: 'Xuất, xem lại PDF, gửi, thay thế, hủy, đồng bộ, tải từ hãng', icon: Icons.request_quote_outlined, module: 'PosEInvoice', screen: const PosEInvoiceReportScreen()),
      (label: 'Thuế hộ kinh doanh', subtitle: 'Dưới 1 tỷ / 1–3 tỷ / trên 3 tỷ', icon: Icons.request_quote_outlined, module: 'HkdBooks', screen: const PosHkdBooksScreen()),
      (label: 'Sổ khách lưu trú', subtitle: 'Khai báo tạm trú', icon: Icons.hotel_outlined, module: 'PosReportStayGuests', screen: const AnalyticsReportViewer(spec: AnalyticsReportSpec.stayGuests)),
      (label: 'Thẻ tập sắp hết hạn', subtitle: 'Gym / spa — nhắc gia hạn', icon: Icons.fitness_center_outlined, module: 'PosReportSessionExpiry', screen: const AnalyticsReportViewer(spec: AnalyticsReportSpec.sessionExpiry)),
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
          // Nằm trong khung chính (thanh trên đã ghi «Báo cáo POS») → không lặp tiêu đề.
          if (Navigator.of(context).canPop())
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
                      fontSize: 16,
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
                borderRadius: BorderRadius.circular(14),
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
                  borderRadius: BorderRadius.circular(14),
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
  SboxColors.violet,
  SboxColors.warningText,
  Color(0xFFBE123C),
  SboxColors.slate600,
];

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Giờ từ API là UTC (thường thiếu «Z») → đổi sang giờ máy; trước đây đọc như giờ địa phương nên lệch 7 tiếng.
DateTime? _parseDate(dynamic v) => parseApiUtcDateTime(v);

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

const _invoiceExcelHeaders = [
  'Mã HĐ',
  'Ngày',
  'Khách',
  'PTTT',
  'NV',
  'Voucher',
  'Tạm tính',
  'CK',
  'VAT',
  'Tổng',
  'Đã thu',
];

List<List<dynamic>> _invoiceExcelRows(List<Map<String, dynamic>> orders) => [
      for (final e in orders)
        [
          e['orderNo'] ?? '',
          _fmtDt(e['saleDate'] ?? e['createdAt']),
          e['customerName'] ?? '',
          e['paymentMethod'] ?? '',
          e['soldBy'] ?? e['createdBy'] ?? '',
          e['voucherCode'] ?? '',
          _n(e['subTotal']),
          _n(e['discount']),
          _n(e['vatAmount']),
          _n(e['total']),
          _n(e['paidAmount']),
        ],
    ];

Future<(int total, List<Map<String, dynamic>> items)> _fetchSalesOrders(
  ApiService api, {
  required DateTime? from,
  required DateTime? to,
  String? soldBy,
  String? paymentMethod,
  String? customerId,
  String? productId,
  String? voucherCode,
  bool hasVoucher = false,
  int pageSize = 40,
}) async {
  final or = await api.getPosSalesReportOrders(
    from: from,
    to: to,
    page: 1,
    pageSize: pageSize,
    soldBy: soldBy,
    paymentMethod: paymentMethod,
    customerId: customerId,
    productId: productId,
    voucherCode: voucherCode,
    hasVoucher: hasVoucher ? true : null,
  );
  if (or['isSuccess'] == true && or['data'] is Map) {
    final d = Map<String, dynamic>.from(or['data'] as Map);
    return (_n(d['total']).toInt(), _maps(d['items']));
  }
  return (0, <Map<String, dynamic>>[]);
}

// ─── Biểu đồ đầu báo cáo (SBOX) ─────────────────────────────────────

/// Gộp danh sách theo ngày → (nhãn dd/MM, tổng) theo thứ tự ngày.
({List<String> labels, List<double> values}) _sumByDay(
  List<Map<String, dynamic>> items,
  String dateKey,
  double Function(Map<String, dynamic> e) valueOf,
) {
  final map = <DateTime, double>{};
  for (final e in items) {
    final d = _parseDate(e[dateKey]);
    if (d == null) continue;
    final l = d.isUtc ? d.toLocal() : d;
    final k = DateTime(l.year, l.month, l.day);
    map[k] = (map[k] ?? 0) + valueOf(e);
  }
  final keys = map.keys.toList()..sort();
  return (labels: [for (final k in keys) sboxDayLabel(k)], values: [for (final k in keys) map[k]!]);
}

/// Tóm tắt bán hàng kỳ trước (để tính % so sánh). null nếu kỳ «Toàn thời gian».
Future<Map<String, dynamic>?> _prevSalesSummary(ApiService api, PosKiotTimeFilterState time) async {
  final prev = sboxPreviousRange(time.from, time.to);
  if (prev == null) return null;
  final r = await api.getPosSalesReportSummary(from: prev.$1, to: prev.$2);
  return r['isSuccess'] == true && r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null;
}

const _vsPrev = 'kỳ trước';

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
  bool _exporting = false;
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _prev;
  List<Map<String, dynamic>> _orders = [];
  int _orderTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prevF = _prevSalesSummary(_api, _time);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    final prev = await prevF;
    final or = await _api.getPosSalesReportOrders(
      from: _time.from,
      to: _time.to,
      page: 1,
      pageSize: 30,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _prev = prev;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      if (or['isSuccess'] == true && or['data'] is Map) {
        final d = Map<String, dynamic>.from(or['data'] as Map);
        _orderTotal = _n(d['total']).toInt();
        _orders = _maps(d['items']);
      } else {
        _orderTotal = 0;
        _orders = [];
      }
    });
  }

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final ok = await PosReportExport.serverExcel(
        context: context,
        filePrefix: 'POS_DoanhThu',
        successMessage: 'Đã xuất Excel từng hóa đơn',
        fetch: () => _api.exportPosSalesReportExcel(
          from: _time.from,
          to: _time.to,
        ),
      );
      if (ok || !mounted) return;
      final d = _data;
      if (d == null) return;
      await PosReportExport.excel(
        context: context,
        title: 'Báo cáo doanh thu',
        sheetName: 'Doanh thu',
        filePrefix: 'POS_DoanhThu',
        periodLabel: _time.displayLabel,
        headers: _invoiceExcelHeaders,
        rows: _invoiceExcelRows(_orders),
        summaryLines: [
          'Cửa hàng: ${d['storeName'] ?? ''}',
          'DT chưa VAT: ${_n(d['totalRevenue'])}',
          'VAT: ${_n(d['totalVat'])}',
          'Số HĐ: $_orderTotal',
        ],
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openSale(Map<String, dynamic> e) {
    final id = '${e['id'] ?? e['Id'] ?? ''}';
    unawaited(PosReportOpen.sale(context, id));
  }

  void _openAllSales({String? soldBy, String? paymentMethod}) {
    unawaited(PosReportOpen.sales(
      context,
      from: _time.from,
      to: _time.to,
      soldBy: soldBy,
      paymentMethod: paymentMethod,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _data?['storeName']?.toString() ?? '';
    final revenue = _n(_data?['totalRevenue']);
    final vat = _n(_data?['totalVat']);
    final revenueInclVat = _n(_data?['totalRevenueInclVat']);
    final byDay = _maps(_data?['profitByDay']).isNotEmpty ? _maps(_data?['profitByDay']) : _maps(_data?['byDay']);
    final byPay = _maps(_data?['byPayment']);
    final staff = _maps(_data?['topEmployees']);
    final hasPrev = _prev != null;
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu (chưa VAT)', value: SboxFmt.money(revenue), icon: Icons.payments_outlined,
            current: revenue, previous: hasPrev ? _n(_prev!['totalRevenue']) : null, compareLabel: _vsPrev),
        SboxKpi(label: 'Số hóa đơn', value: SboxFmt.number(_n(_data?['orderCount'])), icon: Icons.receipt_long_outlined, tone: SboxTone.violet,
            current: _n(_data?['orderCount']), previous: hasPrev ? _n(_prev!['orderCount']) : null, compareLabel: _vsPrev),
        SboxKpi(label: 'Đã thu', value: SboxFmt.money(_n(_data?['totalPaid'])), icon: Icons.account_balance_wallet_outlined, tone: SboxTone.success,
            current: _n(_data?['totalPaid']), previous: hasPrev ? _n(_prev!['totalPaid']) : null, compareLabel: _vsPrev),
        SboxKpi(label: 'Hoàn trả', value: SboxFmt.money(_n(_data?['totalRefund'])), icon: Icons.assignment_return_outlined, tone: SboxTone.warning,
            current: _n(_data?['totalRefund']), previous: hasPrev ? _n(_prev!['totalRefund']) : null, higherIsBetter: false, compareLabel: _vsPrev),
      ],
      charts: [
        SboxChartCard(
          title: 'Doanh thu theo ngày',
          subtitle: _time.displayLabel,
          child: SboxBarChart(
            labels: [for (final d in byDay) sboxDayLabel(d['date'])],
            series: [SboxSeries(name: 'Doanh thu', values: [for (final d in byDay) _n(d['revenue'] ?? d['total'])])],
          ),
        ),
        SboxChartCard(
          title: 'Theo phương thức thanh toán',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(_n(_data?['totalPaid'])),
            centerLabel: 'Đã thu',
            slices: [for (final p in byPay) SboxSlice('${p['paymentMethod'] ?? p['method'] ?? 'Khác'}', _n(p['total']))],
          ),
        ),
      ],
    );

    return PosReportMobileScaffold(
      title: 'Doanh thu',
      exportModule: 'PosReportRevenue',
      time: _time,
      pngKey: _pngKey,
      onExportExcel: _exporting ? null : () => unawaited(_exportExcel()),
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
                insight,
                PosReportCard(
                  title: 'Doanh thu bán hàng',
                  subtitle: _time.displayLabel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        onTileTap: (_) => _openAllSales(),
                        tiles: [
                          (label: 'DT chưa VAT', value: revenue, color: PosTheme.kiotBlue),
                          (label: 'VAT', value: vat, color: SboxColors.violet),
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
                        onTileTap: (_) => _openAllSales(),
                        tiles: [
                          (
                            label: 'Hoàn trả',
                            value: _n(_data?['totalRefund']),
                            color: Colors.orange.shade800,
                          ),
                          (
                            label: 'Đã thu',
                            value: _n(_data?['totalPaid']),
                            color: SboxColors.successText,
                          ),
                          (
                            label: 'Giảm giá',
                            value: _n(_data?['totalDiscount']),
                            color: SboxColors.slate700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PosReportBranchFooter(branchName: storeName),
                    ],
                  ),
                ),
                if (byPay.isNotEmpty)
                  PosReportCard(
                    title: 'Theo phương thức',
                    child: PosReportRankList(
                      items: byPay,
                      labelOf: (p) =>
                          '${p['paymentMethod'] ?? p['method'] ?? 'Khác'} · ${ _n(p['count']).toInt()} HĐ',
                      valueOf: (p) => _n(p['total']),
                      moneyFmt: _moneyFmt,
                      onItemTap: (p) => _openAllSales(
                        paymentMethod: '${p['paymentMethod'] ?? p['method'] ?? ''}',
                      ),
                    ),
                  ),
                if (staff.isNotEmpty)
                  PosReportCard(
                    title: 'Theo nhân viên',
                    child: PosReportRankList(
                      items: staff,
                      labelOf: (p) =>
                          '${p['soldBy'] ?? '—'} · ${_n(p['orderCount']).toInt()} HĐ',
                      valueOf: (p) => _n(p['revenue']),
                      moneyFmt: _moneyFmt,
                      onItemTap: (p) => _openAllSales(
                        soldBy: '${p['soldBy'] ?? ''}',
                      ),
                    ),
                  ),
                PosReportCard(
                  title: 'Hóa đơn gốc',
                  subtitle: '$_orderTotal hóa đơn · bấm để mở phiếu',
                  trailing: TextButton(
                    onPressed: _openAllSales,
                    child: Text(tr('Tất cả')),
                  ),
                  child: PosReportInvoiceList(
                    items: _orders,
                    moneyFmt: _moneyFmt,
                    total: _orderTotal,
                    onOpen: _openSale,
                    onSeeAll: _openAllSales,
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
      limit: 500,
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
      headers: const ['Mã SP', 'Hàng hóa', 'SL', 'Doanh thu', 'CK dòng'],
      rows: [
        for (final p in items)
          [
            p['productCode'] ?? p['productId'] ?? '',
            p['productName'] ?? p['name'] ?? '',
            _n(p['qty']),
            _n(p['revenue']),
            _n(p['lineDiscount'] ?? p['discount']),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['topByRevenue']);
    final totalRev = items.fold<double>(0, (a, e) => a + _n(e['revenue']));
    final totalQty = items.fold<double>(0, (a, e) => a + _n(e['qty']));
    final byQty = [...items]..sort((a, b) => _n(b['qty']).compareTo(_n(a['qty'])));
    String nameOf(Map<String, dynamic> p) => p['productName']?.toString() ?? p['name']?.toString() ?? '—';
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu hàng bán', value: SboxFmt.money(totalRev), icon: Icons.payments_outlined, note: _time.displayLabel),
        SboxKpi(label: 'Số lượng bán', value: SboxFmt.number(totalQty), icon: Icons.shopping_cart_outlined, tone: SboxTone.violet, note: 'Tổng các mặt hàng'),
        SboxKpi(label: 'Mặt hàng có bán', value: SboxFmt.number(items.where((e) => _n(e['qty']) > 0).length), icon: Icons.category_outlined, tone: SboxTone.neutral),
        SboxKpi(
            label: 'Bán chạy nhất',
            value: byQty.isEmpty ? '—' : nameOf(byQty.first),
            icon: Icons.local_fire_department_outlined,
            tone: SboxTone.warning,
            note: byQty.isEmpty ? null : 'SL ${SboxFmt.number(_n(byQty.first['qty']))}'),
      ],
      charts: [
        SboxChartCard(
          title: 'Top 10 theo doanh thu',
          child: SboxRankList(maxItems: 10, items: [
            for (final p in items) SboxSlice(nameOf(p), _n(p['revenue']), caption: 'SL ${SboxFmt.number(_n(p['qty']))}'),
          ]),
        ),
        SboxChartCard(
          title: 'Tỷ trọng doanh thu',
          subtitle: '5 mặt hàng lớn nhất + khác',
          child: SboxDonutChart(
            maxSlices: 6,
            centerValue: SboxFmt.compact(totalRev),
            centerLabel: 'Doanh thu',
            slices: [for (final p in items) SboxSlice(nameOf(p), _n(p['revenue']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Hàng hóa bán ra',
      exportModule: 'PosReportSoldGoods',
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
                insight,
                PosReportCard(
                  title: 'Hàng bán trong kỳ',
                  subtitle: 'Bấm món để mở hóa đơn gốc',
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
                    onItemTap: (p) => PosReportOpen.sales(
                      context,
                      from: _time.from,
                      to: _time.to,
                      productId: '${p['productId'] ?? p['id'] ?? ''}',
                      search: '${p['productId'] ?? p['id'] ?? ''}'.isEmpty
                          ? p['productName']?.toString() ?? p['name']?.toString()
                          : null,
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
    final inDay = _sumByDay(receipts, 'date', (e) => _n(e['grandTotal']));
    final bySupplier = <String, double>{};
    for (final e in receipts) {
      final k = e['supplierName']?.toString().trim().isNotEmpty == true ? e['supplierName'].toString() : 'Không rõ NCC';
      bySupplier[k] = (bySupplier[k] ?? 0) + _n(e['grandTotal']);
    }
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Tiền nhập hàng', value: SboxFmt.money(_n(_data?['receiptAmount'])), icon: Icons.move_to_inbox_outlined,
            note: '${_n(_data?['receiptCount']).toInt()} phiếu nhập'),
        SboxKpi(label: 'Trả nhà cung cấp', value: SboxFmt.money(_n(_data?['returnAmount'])), icon: Icons.outbox_outlined, tone: SboxTone.warning,
            note: '${_n(_data?['returnCount']).toInt()} phiếu trả'),
        SboxKpi(label: 'Đã trả tiền NCC', value: SboxFmt.money(_n(_data?['paidInPeriod'])), icon: Icons.price_check_outlined, tone: SboxTone.success),
        SboxKpi(
            label: 'Nhập ròng',
            value: SboxFmt.money(_n(_data?['receiptAmount']) - _n(_data?['returnAmount'])),
            icon: Icons.inventory_outlined,
            tone: SboxTone.violet,
            note: 'Nhập − trả NCC'),
      ],
      charts: [
        SboxChartCard(
          title: 'Giá trị nhập theo ngày',
          subtitle: _time.displayLabel,
          child: SboxBarChart(labels: inDay.labels, series: [SboxSeries(name: 'Nhập hàng', values: inDay.values)]),
        ),
        SboxChartCard(
          title: 'Theo nhà cung cấp',
          child: SboxRankList(items: [for (final e in bySupplier.entries) SboxSlice(e.key, e.value)]),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Báo cáo nhập hàng',
      exportModule: 'PosReportPurchases',
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
                insight,
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
                            color: SboxColors.successText,
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
  String? _pay;
  List<Map<String, dynamic>> _orders = [];
  int _orderTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    final orders = await _fetchSalesOrders(
      _api,
      from: _time.from,
      to: _time.to,
      paymentMethod: _pay,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      _orderTotal = orders.$1;
      _orders = orders.$2;
    });
  }

  void _openSale(Map<String, dynamic> e) {
    unawaited(PosReportOpen.sale(context, '${e['id'] ?? e['Id'] ?? ''}'));
  }

  void _openAll() {
    unawaited(PosReportOpen.sales(
      context,
      from: _time.from,
      to: _time.to,
      paymentMethod: _pay,
    ));
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
    final payLabels = [
      'Tất cả',
      ...rows.map((e) => e['paymentMethod']?.toString() ?? 'Khác'),
    ];
    final paySelected = _pay == null
        ? 0
        : payLabels.indexWhere((l) => l == _pay).clamp(0, payLabels.length - 1);
    final txCount = rows.fold<double>(0, (a, e) => a + _n(e['count']));
    final sortedPay = [...rows]..sort((a, b) => _n(b['total']).compareTo(_n(a['total'])));
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Tổng đã thu', value: SboxFmt.money(total), icon: Icons.account_balance_wallet_outlined, note: _time.displayLabel),
        SboxKpi(label: 'Số giao dịch', value: SboxFmt.number(txCount), icon: Icons.receipt_outlined, tone: SboxTone.violet),
        SboxKpi(
            label: 'Phương thức chính',
            value: sortedPay.isEmpty ? '—' : '${sortedPay.first['paymentMethod'] ?? 'Khác'}',
            icon: Icons.star_outline_rounded,
            tone: SboxTone.success,
            note: sortedPay.isEmpty || total <= 0 ? null : 'Chiếm ${SboxFmt.pct(_n(sortedPay.first['total']) / total * 100)}'),
        SboxKpi(label: 'TB mỗi giao dịch', value: SboxFmt.money(txCount > 0 ? total / txCount : 0), icon: Icons.calculate_outlined, tone: SboxTone.neutral),
      ],
      charts: [
        SboxChartCard(
          title: 'Cơ cấu đã thu',
          subtitle: _time.displayLabel,
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(total),
            centerLabel: 'Đã thu',
            slices: [for (final s in slices) SboxSlice(s.label, s.value, color: s.color)],
          ),
        ),
        SboxChartCard(
          title: 'Số giao dịch theo phương thức',
          child: SboxBarChart(
            valueFormat: (v) => '${SboxFmt.number(v)} GD',
            axisFormat: (v) => SboxFmt.number(v),
            labels: [for (final e in rows) '${e['paymentMethod'] ?? 'Khác'}'],
            series: [SboxSeries(name: 'Giao dịch', values: [for (final e in rows) _n(e['count'])], color: SboxColors.violet)],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Phương thức thanh toán',
      exportModule: 'PosReportPayment',
      time: _time,
      pngKey: _pngKey,
      filterBar: payLabels.length > 1
          ? PosReportChipBar(
              labels: payLabels.take(8).toList(),
              selected: paySelected,
              onSelected: (i) {
                setState(() => _pay = i == 0 ? null : payLabels[i]);
                _load();
              },
            )
          : null,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Phương thức thanh toán',
        sheetName: 'Hoa don',
        filePrefix: 'POS_PTTT',
        periodLabel: _time.displayLabel,
        filterLabel: _pay,
        headers: _invoiceExcelHeaders,
        rows: _invoiceExcelRows(_orders),
        summaryLines: [
          for (final e in rows)
            '${e['paymentMethod'] ?? 'Khác'}: ${_n(e['count']).toInt()} HĐ · ${_moneyFmt.format(_n(e['total']))}',
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
                insight,
                PosReportCard(
                  title: 'Chi tiết theo phương thức',
                  subtitle: 'Bấm để lọc hóa đơn',
                  child: Column(
                    children: [
                      PosReportRankList(
                        items: rows,
                        labelOf: (e) {
                          final name = e['paymentMethod']?.toString() ?? 'Khác';
                          final c = _n(e['count']).toInt();
                          return c > 0 ? '$name · $c giao dịch' : name;
                        },
                        valueOf: (e) => _n(e['total']),
                        moneyFmt: _moneyFmt,
                        onItemTap: (e) {
                          setState(() =>
                              _pay = e['paymentMethod']?.toString());
                          unawaited(_load());
                        },
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: _pay == null
                      ? 'Hóa đơn gốc'
                      : 'Hóa đơn · $_pay',
                  subtitle: '$_orderTotal hóa đơn · bấm để mở phiếu',
                  trailing: TextButton(
                    onPressed: _openAll,
                    child: Text(tr('Tất cả')),
                  ),
                  child: PosReportInvoiceList(
                    items: _orders,
                    moneyFmt: _moneyFmt,
                    total: _orderTotal,
                    onOpen: _openSale,
                    onSeeAll: _openAll,
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
    List<double> aging(Map<String, dynamic>? d, List<Map<String, dynamic>> rows) {
      double sumOf(String key) => rows.fold<double>(0, (a, e) => a + _n(e[key]));
      return [
        _n(d?['sumDebt0To30']) != 0 ? _n(d?['sumDebt0To30']) : sumOf('debt0To30'),
        _n(d?['sumDebt31To60']) != 0 ? _n(d?['sumDebt31To60']) : sumOf('debt31To60'),
        _n(d?['sumDebt61To90']) != 0 ? _n(d?['sumDebt61To90']) : sumOf('debt61To90'),
        _n(d?['sumDebtOver90']) != 0 ? _n(d?['sumDebtOver90']) : sumOf('debtOver90'),
      ];
    }
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Khách hàng nợ', value: SboxFmt.money(_n(_customers?['sumDebt'])), icon: Icons.person_outline, tone: SboxTone.danger,
            note: '${kh.where((e) => _n(e['currentDebt'] ?? e['debt']) > 0).length} khách'),
        SboxKpi(label: 'Nợ khách quá 90 ngày', value: SboxFmt.money(_n(_customers?['sumDebtOver90'])), icon: Icons.warning_amber_rounded, tone: SboxTone.warning,
            note: 'Cần thu hồi gấp'),
        SboxKpi(label: 'Phải trả NCC', value: SboxFmt.money(_n(_suppliers?['sumDebt'])), icon: Icons.local_shipping_outlined, tone: SboxTone.violet,
            note: '${ncc.where((e) => _n(e['currentDebt']) > 0).length} nhà cung cấp'),
        SboxKpi(
            label: 'Chênh lệch thu − trả',
            value: SboxFmt.money(_n(_customers?['sumDebt']) - _n(_suppliers?['sumDebt'])),
            icon: Icons.balance_outlined,
            tone: SboxTone.neutral),
      ],
      charts: [
        SboxChartCard(
          title: 'Tuổi nợ',
          subtitle: 'Khách hàng và nhà cung cấp theo số ngày',
          child: SboxBarChart(
            labels: const ['0–30 ngày', '31–60 ngày', '61–90 ngày', '> 90 ngày'],
            series: [
              if (_party != 2) SboxSeries(name: 'Khách nợ', values: aging(_customers, kh), color: SboxColors.danger),
              if (_party != 1) SboxSeries(name: 'Nợ NCC', values: aging(_suppliers, ncc), color: SboxColors.violet),
            ],
          ),
        ),
        SboxChartCard(
          title: _party == 2 ? 'Nợ NCC lớn nhất' : 'Khách nợ nhiều nhất',
          child: SboxRankList(
            color: _party == 2 ? SboxColors.violet : SboxColors.danger,
            items: _party == 2
                ? [for (final e in ncc) SboxSlice(e['name']?.toString() ?? '—', _n(e['currentDebt']))]
                : [for (final e in kh) SboxSlice(e['name']?.toString() ?? e['customerName']?.toString() ?? '—', _n(e['currentDebt'] ?? e['debt']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Báo cáo công nợ',
      exportModule: 'PosReportDebt',
      time: _time,
      showTimeFilter: true,
      pngKey: _pngKey,
      onTimeChanged: (s) async {
        setState(() => _time = s);
      },
      onRefresh: _load,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo công nợ',
        sheetName: 'Cong no',
        filePrefix: 'POS_CongNo',
        periodLabel: _time.displayLabel,
        filterLabel: [
          'Tất cả',
          'Khách hàng',
          'NCC',
        ][_party] +
            (_includeZero ? ' · gồm dư 0' : ''),
        headers: const [
          'Loại',
          'Mã',
          'Tên',
          'SĐT',
          'Công nợ',
          'HĐ mở',
          '0–30',
          '31–60',
          '61–90',
          '>90',
        ],
        rows: [
          if (_party != 2)
            for (final e in kh)
              [
                'KH',
                e['customerCode'] ?? '',
                e['name'] ?? e['customerName'] ?? '',
                e['phone'] ?? '',
                _n(e['currentDebt'] ?? e['debt']),
                _n(e['openOrderCount']).toInt(),
                _n(e['debt0To30']),
                _n(e['debt31To60']),
                _n(e['debt61To90']),
                _n(e['debtOver90']),
              ],
          if (_party != 1)
            for (final e in ncc)
              [
                'NCC',
                e['supplierCode'] ?? '',
                e['name'] ?? '',
                e['phone'] ?? '',
                _n(e['currentDebt']),
                _n(e['openOrderCount']).toInt(),
                _n(e['debt0To30']),
                _n(e['debt31To60']),
                _n(e['debt61To90']),
                _n(e['debtOver90']),
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
                insight,
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
                            from: _time.from,
                            to: _time.to,
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
  Map<String, dynamic>? _prev;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prevF = _prevSalesSummary(_api, _time);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    final prev = await prevF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _prev = prev;
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
    final days = _maps(_data?['profitByDay']);
    final hasPrev = _prev != null;
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Lợi nhuận gộp', value: SboxFmt.money(profit), icon: Icons.trending_up_rounded, tone: SboxTone.success,
            current: profit, previous: hasPrev ? _n(_prev!['totalProfit']) : null, compareLabel: _vsPrev),
        SboxKpi(label: 'Doanh thu', value: SboxFmt.money(revenue), icon: Icons.payments_outlined,
            current: revenue, previous: hasPrev ? _n(_prev!['totalRevenue']) : null, compareLabel: _vsPrev),
        SboxKpi(label: 'Giá vốn', value: SboxFmt.money(cogs), icon: Icons.inventory_2_outlined, tone: SboxTone.warning,
            current: cogs, previous: hasPrev ? _n(_prev!['totalCogs']) : null, higherIsBetter: false, compareLabel: _vsPrev),
        SboxKpi(label: 'Biên lợi nhuận', value: SboxFmt.pct(margin), icon: Icons.percent_rounded, tone: SboxTone.violet,
            current: margin, previous: hasPrev ? _n(_prev!['profitMarginPct']) : null, compareLabel: _vsPrev),
      ],
      charts: [
        SboxChartCard(
          title: 'Doanh thu – giá vốn – lợi nhuận',
          subtitle: _time.displayLabel,
          wide: true,
          child: SboxLineChart(
            labels: [for (final d in days) sboxDayLabel(d['date'])],
            series: [
              SboxSeries(name: 'Doanh thu', values: [for (final d in days) _n(d['revenue'])]),
              SboxSeries(name: 'Giá vốn', values: [for (final d in days) _n(d['cogs'])], color: SboxColors.warning),
              SboxSeries(name: 'Lợi nhuận', values: [for (final d in days) _n(d['profit'])], color: SboxColors.success),
            ],
          ),
        ),
      ],
    );

    return PosReportMobileScaffold(
      title: 'Báo cáo lợi nhuận',
      exportModule: 'PosReportProfit',
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
                insight,
                PosReportCard(
                  title: 'Lợi nhuận gộp',
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
                          (label: 'Lợi nhuận', value: profit, color: SboxColors.successText),
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
    final expDay = _sumByDay(items, 'transactionDate', (e) => _n(e['amount']));
    final sortedCats = [...cats]..sort((a, b) => _n(b['total']).compareTo(_n(a['total'])));
    final totalExp = _n(_data?['total']);
    final dayCount = expDay.labels.isEmpty ? 0 : expDay.labels.length;
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(
            label: 'Tổng chi phí',
            value: SboxFmt.money(totalExp),
            icon: Icons.money_off_csred_outlined,
            tone: SboxTone.danger,
            // Tiền nhập hàng / hoàn trả khách / hoàn cọc không phải chi phí (khớp KQKD) — ghi rõ để khỏi thắc mắc.
            note: _n(_data?['excludedTotal']) > 0
                ? 'Không tính ${SboxFmt.money(_n(_data?['excludedTotal']))} nhập hàng / hoàn trả'
                : _time.displayLabel),
        SboxKpi(label: 'Số phiếu chi', value: SboxFmt.number(_n(_data?['count'])), icon: Icons.receipt_outlined, tone: SboxTone.neutral),
        SboxKpi(
            label: 'Khoản chi lớn nhất',
            value: sortedCats.isEmpty ? '—' : '${sortedCats.first['category'] ?? 'Khác'}',
            icon: Icons.pie_chart_outline_rounded,
            tone: SboxTone.warning,
            note: sortedCats.isEmpty ? null : SboxFmt.money(_n(sortedCats.first['total']))),
        SboxKpi(label: 'Chi TB / ngày có chi', value: SboxFmt.money(dayCount > 0 ? totalExp / dayCount : 0), icon: Icons.calendar_today_outlined, tone: SboxTone.violet),
      ],
      charts: [
        SboxChartCard(
          title: 'Chi theo ngày',
          subtitle: _category ?? 'Tất cả khoản mục',
          child: SboxBarChart(labels: expDay.labels, series: [SboxSeries(name: 'Chi', values: expDay.values, color: SboxColors.danger)]),
        ),
        SboxChartCard(
          title: 'Cơ cấu chi phí',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(totalExp),
            centerLabel: 'Tổng chi',
            slices: [for (final c in cats) SboxSlice('${c['category'] ?? 'Khác'}', _n(c['total']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Báo cáo chi phí',
      exportModule: 'PosReportExpense',
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
        headers: const ['Mã', 'Danh mục', 'Mô tả', 'PTTT', 'Ngày', 'Số tiền'],
        rows: [
          for (final e in items)
            [
              e['transactionCode'] ?? '',
              e['category'] ?? '',
              e['description'] ?? '',
              e['paymentMethod'] ?? '',
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
                insight,
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
  Map<String, dynamic>? _prev;
  String? _staff;
  List<Map<String, dynamic>> _orders = [];
  int _orderTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prevF = _prevSalesSummary(_api, _time);
    final res = await _api.getPosSalesReportSummary(from: _time.from, to: _time.to);
    _prev = await prevF;
    final orders = await _fetchSalesOrders(
      _api,
      from: _time.from,
      to: _time.to,
      soldBy: _staff,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      _orderTotal = orders.$1;
      _orders = orders.$2;
    });
  }

  void _openSale(Map<String, dynamic> e) {
    unawaited(PosReportOpen.sale(context, '${e['id'] ?? e['Id'] ?? ''}'));
  }

  void _openAll() {
    unawaited(PosReportOpen.sales(
      context,
      from: _time.from,
      to: _time.to,
      soldBy: _staff,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final staff = _maps(_data?['topEmployees']);
    String who(Map<String, dynamic> e) => e['soldBy']?.toString().trim().isNotEmpty == true ? e['soldBy'].toString() : '—';
    final staffRev = staff.fold<double>(0, (a, e) => a + _n(e['revenue']));
    final prevStaff = <String, double>{for (final e in _maps(_prev?['topEmployees'])) who(e): _n(e['revenue'])};
    final sortedStaff = [...staff]..sort((a, b) => _n(b['revenue']).compareTo(_n(a['revenue'])));
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu nhân viên bán', value: SboxFmt.money(staffRev), icon: Icons.payments_outlined,
            current: staffRev, previous: _prev == null ? null : prevStaff.values.fold<double>(0, (a, b) => a + b), compareLabel: _vsPrev),
        SboxKpi(label: 'Số nhân viên có bán', value: SboxFmt.number(staff.length), icon: Icons.badge_outlined, tone: SboxTone.violet),
        SboxKpi(label: 'TB / nhân viên', value: SboxFmt.money(staff.isEmpty ? 0 : staffRev / staff.length), icon: Icons.groups_2_outlined, tone: SboxTone.neutral),
        SboxKpi(
            label: 'Bán tốt nhất',
            value: sortedStaff.isEmpty ? '—' : who(sortedStaff.first),
            icon: Icons.emoji_events_outlined,
            tone: SboxTone.success,
            note: sortedStaff.isEmpty ? null : SboxFmt.money(_n(sortedStaff.first['revenue']))),
      ],
      charts: [
        SboxChartCard(
          title: 'Doanh thu kỳ này và kỳ trước',
          subtitle: _time.displayLabel,
          child: SboxBarChart(
            labels: [for (final e in sortedStaff.take(10)) who(e)],
            series: [
              SboxSeries(name: 'Kỳ này', values: [for (final e in sortedStaff.take(10)) _n(e['revenue'])]),
              if (_prev != null)
                SboxSeries(name: 'Kỳ trước', values: [for (final e in sortedStaff.take(10)) prevStaff[who(e)] ?? 0], color: SboxColors.slate300),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Tỷ trọng doanh thu',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(staffRev),
            centerLabel: 'Doanh thu',
            slices: [for (final e in staff) SboxSlice(who(e), _n(e['revenue']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Doanh thu theo nhân viên',
      exportModule: 'PosReportStaffRevenue',
      time: _time,
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Doanh thu theo nhân viên',
        sheetName: 'Hoa don',
        filePrefix: 'POS_DTNhanVien',
        periodLabel: _time.displayLabel,
        filterLabel: _staff,
        headers: _invoiceExcelHeaders,
        rows: _invoiceExcelRows(_orders),
        summaryLines: [
          for (final e in staff)
            '${e['soldBy'] ?? '—'}: ${_n(e['orderCount']).toInt()} HĐ · ${_moneyFmt.format(_n(e['revenue']))}',
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
                insight,
                PosReportCard(
                  title: 'Theo người bán',
                  subtitle: _time.displayLabel,
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
                    onItemTap: (e) {
                      setState(() => _staff = e['soldBy']?.toString());
                      unawaited(_load());
                    },
                  ),
                ),
                PosReportCard(
                  title: _staff == null ? 'Hóa đơn gốc' : 'Hóa đơn · $_staff',
                  subtitle: '$_orderTotal hóa đơn · bấm để mở phiếu',
                  trailing: TextButton(
                    onPressed: _openAll,
                    child: Text(tr('Tất cả')),
                  ),
                  child: PosReportInvoiceList(
                    items: _orders,
                    moneyFmt: _moneyFmt,
                    total: _orderTotal,
                    onOpen: _openSale,
                    onSeeAll: _openAll,
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
    final all = _maps(_data?['items']);
    bool isIncome(Map<String, dynamic> e) => e['type']?.toString().toLowerCase() == 'income';
    final inDay = _sumByDay(all, 'transactionDate', (e) => isIncome(e) ? _n(e['amount']) : 0);
    final outDay = _sumByDay(all, 'transactionDate', (e) => isIncome(e) ? 0 : _n(e['amount']));
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Tổng thu', value: SboxFmt.money(_n(_data?['income'])), icon: Icons.south_west_rounded, tone: SboxTone.success,
            note: '${all.where(isIncome).length} phiếu thu'),
        SboxKpi(label: 'Tổng chi', value: SboxFmt.money(_n(_data?['expense'])), icon: Icons.north_east_rounded, tone: SboxTone.danger,
            note: '${all.where((e) => !isIncome(e)).length} phiếu chi'),
        SboxKpi(label: 'Chênh lệch', value: SboxFmt.money(_n(_data?['net'])), icon: Icons.balance_outlined,
            tone: _n(_data?['net']) < 0 ? SboxTone.danger : SboxTone.brand, note: 'Thu − chi'),
      ],
      charts: [
        SboxChartCard(
          title: 'Thu – chi theo ngày',
          subtitle: _time.displayLabel,
          wide: true,
          child: SboxBarChart(
            labels: inDay.labels,
            series: [
              SboxSeries(name: 'Thu', values: inDay.values, color: SboxColors.success),
              SboxSeries(name: 'Chi', values: outDay.values, color: SboxColors.danger),
            ],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Sổ quỹ',
      exportModule: 'PosReportCashbook',
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
        headers: const ['Mã', 'Loại', 'Danh mục', 'Mô tả', 'PTTT', 'Ngày', 'Số tiền'],
        rows: [
          for (final e in items)
            [
              e['transactionCode'] ?? '',
              e['type'] ?? '',
              e['category'] ?? '',
              e['description'] ?? '',
              e['paymentMethod'] ?? '',
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
                insight,
                PosReportCard(
                  title: 'Thu — chi kỳ',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Thu',
                        value: _n(_data?['income']),
                        color: SboxColors.successText,
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
            color: income ? SboxColors.successText : const Color(0xFFB42318),
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
  List<Map<String, dynamic>> _orders = [];
  int _orderTotal = 0;
  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPnlReport(from: _time.from, to: _time.to);
    final ordersF = _fetchSalesOrders(
      _api,
      from: _time.from,
      to: _time.to,
    );
    final expF = _api.getPosExpenseReport(from: _time.from, to: _time.to);
    final orders = await ordersF;
    final exp = await expF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      _orderTotal = orders.$1;
      _orders = orders.$2;
      _expenses = exp['isSuccess'] == true && exp['data'] is Map
          ? _maps((exp['data'] as Map)['items'])
          : [];
    });
  }

  void _openSale(Map<String, dynamic> e) {
    unawaited(PosReportOpen.sale(context, '${e['id'] ?? e['Id'] ?? ''}'));
  }

  @override
  Widget build(BuildContext context) {
    final net = _n(_data?['netProfit']);
    final expCats = _maps(_data?['expenseByCategory']);
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu', value: SboxFmt.money(_n(_data?['revenue'])), icon: Icons.payments_outlined,
            note: '${_n(_data?['orderCount']).toInt()} hóa đơn'),
        SboxKpi(label: 'Lợi nhuận gộp', value: SboxFmt.money(_n(_data?['grossProfit'])), icon: Icons.trending_up_rounded, tone: SboxTone.success),
        SboxKpi(label: 'Chi phí', value: SboxFmt.money(_n(_data?['expenses']) + _n(_data?['inventoryLoss'])), icon: Icons.money_off_csred_outlined, tone: SboxTone.warning,
            note: _n(_data?['inventoryLoss']) != 0 ? 'Gồm hao hụt kho ${SboxFmt.money(_n(_data?['inventoryLoss']))}' : null),
        SboxKpi(label: 'Lợi nhuận ròng', value: SboxFmt.money(net), icon: Icons.savings_outlined, tone: net < 0 ? SboxTone.danger : SboxTone.success,
            note: 'Biên ${SboxFmt.pct(_n(_data?['marginPct']))}'),
      ],
      charts: [
        SboxChartCard(
          title: 'Từ doanh thu đến lợi nhuận ròng',
          subtitle: _time.displayLabel,
          child: SboxBarChart(
            labels: const ['Doanh thu', 'Giá vốn', 'LN gộp', 'Hao hụt kho', 'Chi phí', 'Thu khác', 'LN ròng'],
            series: [
              SboxSeries(name: 'Số tiền', values: [
                _n(_data?['revenue']),
                _n(_data?['cogs']),
                _n(_data?['grossProfit']),
                _n(_data?['inventoryLoss']),
                _n(_data?['expenses']),
                _n(_data?['otherIncome']),
                net,
              ]),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Cơ cấu chi phí',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(_n(_data?['expenses'])),
            centerLabel: 'Chi phí',
            slices: [for (final c in expCats) SboxSlice('${c['category'] ?? 'Khác'}', _n(c['amount']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Kết quả kinh doanh',
      exportModule: 'PosReportPnl',
      time: _time,
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Kết quả kinh doanh',
        sheetName: 'Hoa don',
        filePrefix: 'POS_KQKD',
        periodLabel: _time.displayLabel,
        headers: _invoiceExcelHeaders,
        rows: _invoiceExcelRows(_orders),
        summaryLines: [
          'Doanh thu: ${_n(_data?['revenue'])}',
          'VAT: ${_n(_data?['vat'])}',
          'Giảm giá: ${_n(_data?['discount'])}',
          'Giá vốn: ${_n(_data?['cogs'])}',
          'LN gộp: ${_n(_data?['grossProfit'])}',
          'Chi phí: ${_n(_data?['expenses'])}',
          'Thu nhập khác: ${_n(_data?['otherIncome'])}',
          'LN ròng: $net',
          'Biên %: ${_n(_data?['marginPct'])}',
          'Số HĐ: $_orderTotal',
          'Phiếu chi: ${_expenses.length}',
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
                insight,
                PosReportCard(
                  title: 'P&L kỳ',
                  subtitle: _time.displayLabel,
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
                            color: SboxColors.violet,
                          ),
                          (
                            label: 'Giảm giá',
                            value: _n(_data?['discount']),
                            color: SboxColors.slate700,
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
                              : SboxColors.successText,
                        ),
                      ),
                    ],
                  ),
                ),
                if ((_data?['lines'] as List?)?.isNotEmpty == true)
                  PosReportCard(
                    title: 'Báo cáo kết quả kinh doanh',
                    subtitle: 'Doanh thu thuần = tiền hàng (chưa VAT) − hàng khách trả',
                    child: Column(
                      children: [
                        for (final l in (_data!['lines'] as List).whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr('${l['label']}'),
                                    style: TextStyle(
                                      fontWeight: const {'10', '20', '50'}
                                              .contains('${l['code']}')
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                Text(
                                  posReportMoney(_n(l['amount'])),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _n(l['amount']) < 0
                                        ? const Color(0xFFB42318)
                                        : SboxColors.successText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if ((_data?['expenseByCategory'] as List?)?.isNotEmpty == true ||
                    (_data?['otherIncomeByCategory'] as List?)?.isNotEmpty == true)
                  PosReportCard(
                    title: 'Chi phí & thu nhập khác theo khoản mục',
                    subtitle: 'Từ sổ quỹ — không gồm nhập hàng, tiền bán hàng, cọc, trả hàng',
                    child: Column(
                      children: [
                        for (final c in ((_data?['expenseByCategory'] as List?) ?? const [])
                            .whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(child: Text(tr('${c['category']} (${c['count']})'))),
                              PosReportMoneyLabel(_n(c['amount']), prefix: '-'),
                            ]),
                          ),
                        for (final c in ((_data?['otherIncomeByCategory'] as List?) ?? const [])
                            .whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(child: Text(tr('${c['category']} (${c['count']})'))),
                              PosReportMoneyLabel(_n(c['amount']), prefix: '+'),
                            ]),
                          ),
                      ],
                    ),
                  ),
                PosReportCard(
                  title: 'Hóa đơn gốc',
                  subtitle: '$_orderTotal hóa đơn · bấm để mở phiếu',
                  trailing: TextButton(
                    onPressed: () => unawaited(PosReportOpen.sales(
                      context,
                      from: _time.from,
                      to: _time.to,
                    )),
                    child: Text(tr('Tất cả')),
                  ),
                  child: PosReportInvoiceList(
                    items: _orders,
                    moneyFmt: _moneyFmt,
                    total: _orderTotal,
                    onOpen: _openSale,
                    onSeeAll: () => unawaited(PosReportOpen.sales(
                      context,
                      from: _time.from,
                      to: _time.to,
                    )),
                  ),
                ),
                if (_expenses.isNotEmpty)
                  PosReportCard(
                    title: 'Phiếu chi kỳ',
                    child: Column(
                      children: [
                        for (var i = 0; i < _expenses.take(20).length; i++) ...[
                          if (i > 0) const Divider(height: 14),
                          PosReportNavRow(
                            onTap: () => PosReportOpen.cashTx(
                                context, _expenses[i]),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_expenses[i]['transactionCode'] ?? _expenses[i]['category'] ?? 'Chi'} · ${_fmtDt(_expenses[i]['transactionDate'])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PosReportMoneyLabel(
                                  _n(_expenses[i]['amount']),
                                  prefix: '-',
                                  color: const Color(0xFFB42318),
                                ),
                              ],
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
  String? _code;
  List<Map<String, dynamic>> _orders = [];
  int _orderTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosVoucherReport(from: _time.from, to: _time.to);
    final orders = await _fetchSalesOrders(
      _api,
      from: _time.from,
      to: _time.to,
      voucherCode: _code,
      hasVoucher: _code == null,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
      _orderTotal = orders.$1;
      _orders = orders.$2;
    });
  }

  void _openSale(Map<String, dynamic> e) {
    unawaited(PosReportOpen.sale(context, '${e['id'] ?? e['Id'] ?? ''}'));
  }

  void _openAll() {
    unawaited(PosReportOpen.sales(
      context,
      from: _time.from,
      to: _time.to,
      voucherCode: _code,
      hasVoucher: _code == null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _maps(_data?['items']);
    final uses = _n(_data?['uses']);
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Tiền giảm bằng voucher', value: SboxFmt.money(_n(_data?['totalDiscount'])), icon: Icons.local_offer_outlined, tone: SboxTone.warning),
        SboxKpi(label: 'Doanh thu kèm voucher', value: SboxFmt.money(_n(_data?['revenueWithVoucher'])), icon: Icons.payments_outlined),
        SboxKpi(label: 'Lượt dùng', value: SboxFmt.number(uses), icon: Icons.confirmation_number_outlined, tone: SboxTone.violet,
            note: '${items.length} mã voucher'),
        SboxKpi(
            label: 'Giảm TB / lượt',
            value: SboxFmt.money(uses > 0 ? _n(_data?['totalDiscount']) / uses : 0),
            icon: Icons.calculate_outlined,
            tone: SboxTone.neutral),
      ],
      charts: [
        SboxChartCard(
          title: 'Doanh thu mang về theo mã',
          child: SboxRankList(items: [
            for (final e in items) SboxSlice('${e['voucherCode'] ?? '—'}', _n(e['revenue']), caption: '${_n(e['uses']).toInt()} lượt'),
          ]),
        ),
        SboxChartCard(
          title: 'Tiền giảm theo mã',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(_n(_data?['totalDiscount'])),
            centerLabel: 'Đã giảm',
            slices: [for (final e in items) SboxSlice('${e['voucherCode'] ?? '—'}', _n(e['discount']))],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Báo cáo voucher',
      exportModule: 'PosReportVoucher',
      time: _time,
      pngKey: _pngKey,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Báo cáo voucher',
        sheetName: 'Hoa don',
        filePrefix: 'POS_Voucher',
        periodLabel: _time.displayLabel,
        filterLabel: _code,
        headers: _invoiceExcelHeaders,
        rows: _invoiceExcelRows(_orders),
        summaryLines: [
          'Tổng giảm: ${_moneyFmt.format(_n(_data?['totalDiscount']))}',
          'DT kèm VC: ${_moneyFmt.format(_n(_data?['revenueWithVoucher']))}',
          for (final e in items)
            '${e['voucherCode']}: ${_n(e['uses']).toInt()} lượt · CK ${_moneyFmt.format(_n(e['discount']))} · DT ${_moneyFmt.format(_n(e['revenue']))}',
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
                insight,
                PosReportCard(
                  title: 'Sử dụng voucher',
                  subtitle: _time.displayLabel,
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
                            color: SboxColors.successText,
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
                        onItemTap: (e) {
                          setState(() =>
                              _code = e['voucherCode']?.toString());
                          unawaited(_load());
                        },
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: _code == null
                      ? 'Hóa đơn dùng voucher'
                      : 'Hóa đơn · $_code',
                  subtitle: '$_orderTotal hóa đơn · bấm để mở phiếu',
                  trailing: TextButton(
                    onPressed: _openAll,
                    child: Text(tr('Tất cả')),
                  ),
                  child: PosReportInvoiceList(
                    items: _orders,
                    moneyFmt: _moneyFmt,
                    total: _orderTotal,
                    onOpen: _openSale,
                    onSeeAll: _openAll,
                  ),
                ),
              ],
            ),
    );
  }
}
