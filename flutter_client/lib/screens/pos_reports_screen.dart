import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../utils/pos_report_export.dart';
import '../utils/pos_report_open.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
import '../widgets/sbox/sbox_table.dart';
import '../widgets/sbox/sbox_charts.dart';
import '../widgets/sbox/sbox_basics.dart';
import '../widgets/sbox/sbox_report.dart';
const _kiotBlue = PosTheme.kiotBlue;

/// Báo cáo POS: doanh thu + tồn kho + lô/HSD (API `/api/pos/reports/*`).
class PosReportsScreen extends StatefulWidget {
  const PosReportsScreen({
    super.key,
    this.initialTab = 0,
    this.lockTab = false,
  });

  final int initialTab;
  final bool lockTab;

  @override
  State<PosReportsScreen> createState() => _PosReportsScreenState();
}

class _PosReportsScreenState extends State<PosReportsScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  /// Số lượng giữ phần lẻ (97,5 kg) — SboxFmt.number làm tròn thành số nguyên.
  static final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  static String _fq(num v) => _qtyFmt.format(v);
  final _stockSearchCtrl = TextEditingController();
  // Ô tìm riêng cho tab lô — trước đây dùng chung ô tìm của Tồn kho.
  final _lotSearchCtrl = TextEditingController();
  final _salesPngKey = GlobalKey();
  final _stockPngKey = GlobalKey();
  final _lotPngKey = GlobalKey();

  late final TabController _tabs;
  PosKiotTimeFilterState _salesTime = PosKiotTimeFilterState.thisMonth();
  bool _loadingSales = false;
  bool _loadingStock = false;
  bool _loadingLots = false;
  bool _exporting = false;
  Map<String, dynamic>? _salesSummary;
  Map<String, dynamic>? _stockSummary;
  Map<String, dynamic>? _lotSummary;
  List<Map<String, dynamic>> _stockProducts = [];
  List<Map<String, dynamic>> _stockTopValue = [];
  List<Map<String, dynamic>> _lotItems = [];
  int _stockTotal = 0;
  int _lotTotal = 0;
  double _stockFilteredValue = 0;
  double _lotFilteredValue = 0;
  int _stockPage = 1;
  int _lotPage = 1;
  /// Mặc định «Cần xử lý» (đã hết + sắp hết) — màn «Hàng sắp hết hạn» trước đây mở ra tất cả lô.
  String _lotFilter = 'attention';
  String? _stockFilter;
  String _stockSort = 'default';
  String? _stockError;
  String? _lotError;
  bool _salesFilterOpen = false;
  static const _stockPageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabs.addListener(_onTabChanged);
    _loadTabData(_tabs.index);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    _loadTabData(_tabs.index);
  }

  void _loadTabData(int index) {
    switch (index) {
      case 0:
        if (_salesSummary == null && !_loadingSales) unawaited(_loadSales());
        break;
      case 1:
        if (_stockSummary == null && !_loadingStock) unawaited(_loadStock(withSummary: true));
        break;
      case 2:
        if (_lotSummary == null && !_loadingLots) unawaited(_loadLots(withSummary: true));
        break;
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _stockDebounce?.cancel();
    _stockSearchCtrl.dispose();
    _lotSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _loadingSales = true);
    final res = await _api.getPosSalesReportSummary(
      from: _salesTime.from,
      to: _salesTime.to,
    );
    if (!mounted) return;
    setState(() {
      _loadingSales = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _salesSummary = Map<String, dynamic>.from(res['data'] as Map);
      }
    });
  }

  List<Map<String, dynamic>> _mapsOf(dynamic v) =>
      ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  String? _search(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Tổng hợp (KPI, biểu đồ) chỉ tải lần đầu / khi kéo làm mới — không phụ thuộc ô tìm, bộ lọc, trang.
  Future<void> _loadStock({int page = 1, bool withSummary = false}) async {
    setState(() => _loadingStock = true);
    final listF = _api.getPosStockReportProducts(
      search: _search(_stockSearchCtrl),
      filter: _stockFilter,
      page: page,
      pageSize: _stockPageSize,
      sort: _stockSort == 'default' ? null : _stockSort,
    );
    final sumF = withSummary || _stockSummary == null ? _api.getPosStockReportSummary() : null;
    final topF = withSummary || _stockSummary == null
        ? _api.getPosStockReportProducts(page: 1, pageSize: 8, sort: 'value')
        : null;
    final listRes = await listF;
    final sumRes = await sumF;
    final topRes = await topF;
    if (!mounted) return;
    setState(() {
      _loadingStock = false;
      _stockPage = page;
      if (sumRes != null && sumRes['isSuccess'] == true && sumRes['data'] is Map) {
        _stockSummary = Map<String, dynamic>.from(sumRes['data'] as Map);
      }
      if (topRes != null && topRes['isSuccess'] == true && topRes['data'] is Map) {
        _stockTopValue = _mapsOf((topRes['data'] as Map)['items']);
      }
      if (listRes['isSuccess'] == true && listRes['data'] is Map) {
        final data = listRes['data'] as Map;
        _stockError = null;
        _stockTotal = (data['total'] as num?)?.toInt() ?? 0;
        _stockFilteredValue = _num(data['totalValue']);
        _stockProducts = _mapsOf(data['items']);
      } else {
        _stockError = listRes['message']?.toString() ?? 'Không tải được tồn kho';
      }
    });
  }

  Future<void> _loadLots({int page = 1, bool withSummary = false}) async {
    setState(() => _loadingLots = true);
    final listF = _api.getPosStockLotReport(
      search: _search(_lotSearchCtrl),
      filter: _lotFilter == 'all' ? null : _lotFilter,
      page: page,
      pageSize: _stockPageSize,
    );
    final sumF = withSummary || _lotSummary == null ? _api.getPosStockLotReportSummary() : null;
    final listRes = await listF;
    final sumRes = await sumF;
    if (!mounted) return;
    setState(() {
      _loadingLots = false;
      _lotPage = page;
      if (sumRes != null && sumRes['isSuccess'] == true && sumRes['data'] is Map) {
        _lotSummary = Map<String, dynamic>.from(sumRes['data'] as Map);
      }
      if (listRes['isSuccess'] == true && listRes['data'] is Map) {
        final data = listRes['data'] as Map;
        _lotError = null;
        _lotTotal = (data['total'] as num?)?.toInt() ?? 0;
        _lotFilteredValue = _num(data['totalValue']);
        _lotItems = _mapsOf(data['items']);
      } else {
        _lotError = listRes['message']?.toString() ?? 'Không tải được danh sách lô';
      }
    });
  }

  Future<void> _exportSales() async {
    setState(() => _exporting = true);
    try {
      final res = await _api.exportPosSalesReportExcel(
        from: _salesTime.from,
        to: _salesTime.to,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'bao_cao_doanh_thu_pos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất file', message: tr('Đã xuất Excel doanh thu'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportStock() async {
    setState(() => _exporting = true);
    try {
      // Cùng bộ lọc với màn hình (trước đây Excel bỏ qua «Tình trạng»).
      final res = await _api.exportPosStockReportExcel(
        search: _search(_stockSearchCtrl),
        filter: _stockFilter,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'bao_cao_ton_kho_pos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất file', message: tr('Đã xuất Excel tồn kho'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Xuất đủ mọi lô theo bộ lọc (trước đây chỉ xuất 30 lô của trang đang xem, HSD dạng chuỗi ISO).
  Future<void> _exportLots() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final all = <Map<String, dynamic>>[];
    try {
      for (var page = 1; page <= 40; page++) {
        final res = await _api.getPosStockLotReport(
          search: _search(_lotSearchCtrl),
          filter: _lotFilter == 'all' ? null : _lotFilter,
          page: page,
          pageSize: 500,
        );
        if (res['isSuccess'] != true || res['data'] is! Map) break;
        final data = res['data'] as Map;
        final items = _mapsOf(data['items']);
        all.addAll(items);
        if (items.length < 500 || all.length >= ((data['total'] as num?)?.toInt() ?? 0)) break;
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    final dateFmt = DateFormat('dd/MM/yyyy');
    String d(dynamic raw) {
      final v = raw == null ? null : DateTime.tryParse('$raw');
      return v == null ? '' : dateFmt.format(v);
    }

    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo hàng theo lô / hạn dùng',
      sheetName: 'Lo HSD',
      filePrefix: 'POS_LoHSD',
      filterLabel: _lotFilterOptions[_lotFilter],
      summaryLines: [
        '${all.length} lô · giá trị ${SboxFmt.money(all.fold<double>(0, (a, l) => a + _num(l['stockValue'])))}',
      ],
      headers: const ['Mã hàng', 'Hàng hóa', 'ĐVT', 'Lô', 'NSX', 'HSD', 'Còn (ngày)', 'SL', 'Giá vốn', 'Giá trị', 'Trạng thái'],
      rows: [
        for (final l in all)
          [
            l['productCode'] ?? '',
            l['productName'] ?? '',
            l['unitName'] ?? '',
            l['lotNo'] ?? '',
            d(l['manufactureDate']),
            d(l['expiryDate']),
            l['daysUntilExpiry'] ?? '',
            _num(l['qtyOnHand']),
            _num(l['unitCost']),
            _num(l['stockValue']),
            _lotStatusLabel('${l['status']}'),
          ],
      ],
    );
  }

  static const _lotFilterOptions = {
    'attention': 'Cần xử lý',
    'expiring': 'Sắp hết HSD',
    'expired': 'Đã hết HSD',
    'ok': 'Còn hạn',
    'noexpiry': 'Không ghi HSD',
    'all': 'Tất cả lô',
  };

  static String _lotStatusLabel(String? status) => switch (status) {
        'expired' => 'Hết HSD',
        'expiring' => 'Sắp hết',
        'noexpiry' => 'Không HSD',
        _ => 'Còn hạn',
      };

  static SboxTone _lotStatusTone(String? status) => switch (status) {
        'expired' => SboxTone.danger,
        'expiring' => SboxTone.warning,
        'noexpiry' => SboxTone.neutral,
        _ => SboxTone.success,
      };

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canView = perm.canView('PosSalesReport') ||
        perm.canView('PosProducts') ||
        perm.canView('PosReportStock') ||
        perm.canView('PosReportExpiry');
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Báo cáo POS'))),
        body: Center(child: Text(tr('Không có quyền xem báo cáo POS'))),
      );
    }
    final canExport = perm.canExport('PosSalesReport') || perm.canExport('PosProducts');
    final canExportStock = perm.canExport('PosReportStock') || perm.canExport('PosProducts');
    final canExportLots = perm.canExport('PosReportExpiry') || perm.canExport('PosProducts');
    final mobile = posUseMobileList(context);

    final pushed = PosHubScope.pushedSubPageOf(context);
    final showHeader = widget.lockTab ||
        pushed ||
        HrmPageChrome.isPushedOverShell(context);

    return Scaffold(
      backgroundColor: SboxColors.slate100,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            PosMobileKiotHeader(
              title: switch (widget.initialTab) {
                1 => 'Tồn kho',
                2 => 'Hàng sắp hết hạn',
                _ => widget.lockTab ? 'Doanh thu' : 'Báo cáo',
              },
            )
          else
            const PosModuleToolbar(activeModule: 'PosSalesReport'),
          if (!widget.lockTab)
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                labelColor: _kiotBlue,
                indicatorColor: _kiotBlue,
                isScrollable: mobile,
                tabAlignment: mobile ? TabAlignment.start : TabAlignment.fill,
                tabs: [
                  Tab(text: tr(mobile ? 'Doanh thu' : 'Doanh thu bán hàng')),
                  Tab(text: tr('Tồn kho')),
                  Tab(text: tr(mobile ? 'Lô/HSD' : 'Lô / HSD')),
                ],
              ),
            ),
          Expanded(
            child: widget.lockTab
                ? switch (widget.initialTab) {
                    1 => _buildStockTab(canExportStock),
                    2 => _buildLotsTab(canExportLots),
                    _ => _buildSalesTab(canExport),
                  }
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildSalesTab(canExport),
                      _buildStockTab(canExportStock),
                      _buildLotsTab(canExportLots),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTab(bool canExport) {
    final mobile = posUseMobileList(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: mobile
              ? PosFilterCollapse(
                  expanded: _salesFilterOpen,
                  onToggle: () =>
                      setState(() => _salesFilterOpen = !_salesFilterOpen),
                  title: 'Kỳ báo cáo',
                  subtitle: _salesTime.displayLabel,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PosKiotTimeFilter(
                      state: _salesTime,
                      onChanged: (s) {
                        setState(() => _salesTime = s);
                        _loadSales();
                      },
                    ),
                    if (canExport) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: _kiotBlue),
                              onPressed: _exporting ? null : _exportSales,
                              icon: const Icon(Icons.download, size: 18),
                              label: Text(tr('Xuất Excel')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => PosReportExport.png(
                              context: context,
                              key: _salesPngKey,
                              filePrefix: 'POS_DoanhThu',
                            ),
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(tr('PNG')),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 420,
                        child: PosKiotTimeFilter(
                          state: _salesTime,
                          onChanged: (s) {
                            setState(() => _salesTime = s);
                            _loadSales();
                          },
                        ),
                      ),
                      if (canExport) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: _kiotBlue),
                          onPressed: _exporting ? null : _exportSales,
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(tr('Excel')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => PosReportExport.png(
                            context: context,
                            key: _salesPngKey,
                            filePrefix: 'POS_DoanhThu',
                          ),
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: Text(tr('PNG')),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        Expanded(
          child: _loadingSales
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : _salesSummary == null
                  ? Center(child: Text(tr('Không có dữ liệu')))
                  : RepaintBoundary(
                      key: _salesPngKey,
                      child: _buildSalesBody(_salesSummary!),
                    ),
        ),
      ],
    );
  }

  Widget _buildSalesBody(Map<String, dynamic> s) {
    final topProducts = (s['topProducts'] as List?) ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('Tổng quan', [
          _row('Số đơn', '${s['orderCount'] ?? 0}'),
          _row('Doanh thu (chưa VAT)', _moneyFmt.format(_num(s['totalRevenue']))),
          _row('VAT', _moneyFmt.format(_num(s['totalVat']))),
          _row('Doanh thu gồm VAT', _moneyFmt.format(_num(s['totalRevenueInclVat']))),
          _row('Hoàn trả trong kỳ', _moneyFmt.format(_num(s['totalRefund']))),
          _row('Đã thu', _moneyFmt.format(_num(s['totalPaid']))),
          _row('Giảm giá', _moneyFmt.format(_num(s['totalDiscount']))),
          _row('Giá vốn', _moneyFmt.format(_num(s['totalCogs']))),
          _row('Lợi nhuận', _moneyFmt.format(_num(s['totalProfit']))),
          _row('Biên LN', '${_num(s['profitMarginPct']).toStringAsFixed(1)}%'),
        ]),
        const SizedBox(height: 12),
        if (((s['byPayment'] as List?) ?? []).isNotEmpty)
          _card('Theo thanh toán', [
            for (final p in (s['byPayment'] as List))
              if (p is Map)
                _row(
                  p['paymentMethod']?.toString() ?? 'Khác',
                  '${_moneyFmt.format(_num(p['total']))} (${p['count'] ?? 0})',
                  onTap: () => PosReportOpen.sales(context,
                      from: _salesTime.from, to: _salesTime.to, paymentMethod: p['paymentMethod']?.toString()),
                ),
          ]),
        if (((s['byPayment'] as List?) ?? []).isNotEmpty) const SizedBox(height: 12),
        if (((s['byDay'] as List?) ?? []).isNotEmpty)
          _card('Theo ngày', [
            for (final d in (s['byDay'] as List).take(14))
              if (d is Map)
                _row(
                  _fmtDay(d['date']),
                  '${_moneyFmt.format(_num(d['total']))} (${d['count'] ?? 0} đơn)',
                  onTap: () {
                    final day = DateTime.tryParse('${d['date']}');
                    PosReportOpen.sales(context,
                        from: day == null ? _salesTime.from : DateTime(day.year, day.month, day.day),
                        to: day == null ? _salesTime.to : DateTime(day.year, day.month, day.day, 23, 59, 59));
                  },
                ),
          ]),
        if (((s['byDay'] as List?) ?? []).isNotEmpty) const SizedBox(height: 12),
        if (((s['topEmployees'] as List?) ?? []).isNotEmpty)
          _card('Top nhân viên', [
            for (final e in (s['topEmployees'] as List).take(10))
              if (e is Map)
                _row(
                  ((e['displayName'] ?? e['soldBy'])?.toString().trim().isNotEmpty == true)
                      ? (e['displayName'] ?? e['soldBy']).toString()
                      : '—',
                  '${_moneyFmt.format(_num(e['revenue']))} (${e['orderCount'] ?? 0})',
                  onTap: () => PosReportOpen.sales(context,
                      from: _salesTime.from, to: _salesTime.to, soldBy: e['soldBy']?.toString(), soldByLabel: e['displayName']?.toString()),
                ),
          ]),
        if (((s['topEmployees'] as List?) ?? []).isNotEmpty) const SizedBox(height: 12),
        if (topProducts.isNotEmpty)
          _card('Top hàng bán', [
            for (final p in topProducts)
              if (p is Map)
                _row(
                  p['productName']?.toString() ?? '',
                  '${_moneyFmt.format(_num(p['revenue']))} (${p['qty']})',
                  onTap: () => PosReportOpen.productMenu(context,
                      id: '${p['productId'] ?? ''}',
                      name: '${p['productName'] ?? ''}',
                      from: _salesTime.from,
                      to: _salesTime.to),
                ),
          ]),
      ],
    );
  }



  Timer? _stockDebounce;

  void _onStockSearch(String _, VoidCallback reload) {
    _stockDebounce?.cancel();
    _stockDebounce = Timer(const Duration(milliseconds: 400), reload);
  }

  Widget _exportButtons({required VoidCallback? onExcel, required VoidCallback onPng}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SboxButton.secondary(label: 'Excel', icon: Icons.download_outlined, onPressed: onExcel),
          const SizedBox(width: SboxSpace.sm),
          SboxButton.secondary(label: 'PNG', icon: Icons.image_outlined, onPressed: onPng),
        ],
      );

  Widget _reportPager({required int page, required int pages, required int total, required String label, required ValueChanged<int> onPage}) {
    if (pages <= 1) return const SizedBox.shrink();
    if (posUseMobileList(context)) {
      return PosMobilePager(total: total, page: page, pageSize: _stockPageSize, label: label, onPageChanged: onPage);
    }
    return SboxPager(page: page, pageSize: _stockPageSize, total: total, onPage: onPage);
  }

  /// Vùng nội dung báo cáo: đang tải lại thì giữ bảng cũ + thanh tiến trình mảnh (trước đây mỗi lần gõ tìm cả màn
  /// thành vòng quay); lỗi tải thì báo lỗi + «Thử lại» thay vì bảng trống như «không có hàng».
  Widget _reportBody({
    required bool loading,
    required bool hasData,
    required String? error,
    required VoidCallback onRetry,
    required Widget child,
  }) {
    if (loading && !hasData) {
      return const Center(child: CircularProgressIndicator(color: _kiotBlue));
    }
    if (error != null && !hasData) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(error), style: SboxType.bodyStyle(SboxColors.dangerText)),
          const SizedBox(height: SboxSpace.sm),
          SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh, onPressed: onRetry),
        ]),
      );
    }
    return Column(children: [
      SizedBox(height: 2, child: loading ? const LinearProgressIndicator(color: _kiotBlue, minHeight: 2) : null),
      Expanded(child: child),
    ]);
  }

  static String _stockStatusLabel(String? s) => switch (s) {
        'OutOfStock' => 'Hết hàng',
        'BelowMin' => 'Dưới tối thiểu',
        'AboveMax' => 'Vượt tối đa',
        _ => 'Đủ hàng',
      };

  static SboxTone _stockStatusTone(String? s) => switch (s) {
        'OutOfStock' => SboxTone.danger,
        'BelowMin' => SboxTone.warning,
        'AboveMax' => SboxTone.violet,
        _ => SboxTone.success,
      };

  void _setStockFilter(String? f) {
    setState(() => _stockFilter = f);
    _loadStock();
  }

  /// Tồn kho: một hàng lọc (tìm · tình trạng · sắp xếp · Excel/PNG), số liệu + bảng.
  Widget _buildStockTab(bool canExport) {
    final totalPages = (_stockTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    String qty(dynamic v) => _fq(_num(v));
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 4),
          child: SboxFilterBar(
            searchHint: 'Tìm tên, mã hàng, mã vạch',
            searchController: _stockSearchCtrl,
            onSearch: (v) => _onStockSearch(v, () => _loadStock()),
            filters: [
              SboxFilterChip<String>(
                label: 'Tình trạng',
                value: _stockFilter ?? 'all',
                options: const {'all': 'Tất cả', 'OutOfStock': 'Hết hàng', 'BelowMin': 'Dưới tối thiểu', 'AboveMax': 'Vượt tối đa'},
                onChanged: (v) => _setStockFilter(v == 'all' ? null : v),
              ),
              // Sắp xếp trên toàn bộ danh sách (máy chủ) — bấm tiêu đề cột trước đây chỉ sắp trong trang.
              SboxFilterChip<String>(
                label: 'Sắp xếp',
                value: _stockSort,
                options: const {
                  'default': 'Cần xử lý trước',
                  'value': 'Giá trị tồn cao',
                  'qty': 'Tồn nhiều',
                  'qtyasc': 'Tồn ít',
                  'name': 'Tên A→Z',
                },
                onChanged: (v) {
                  setState(() => _stockSort = v);
                  _loadStock();
                },
              ),
            ],
            actions: [
              if (canExport)
                _exportButtons(
                  onExcel: _exporting ? null : _exportStock,
                  onPng: () => PosReportExport.png(context: context, key: _stockPngKey, filePrefix: 'POS_TonKho'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _reportBody(
            loading: _loadingStock,
            hasData: _stockSummary != null || _stockProducts.isNotEmpty,
            error: _stockError,
            onRetry: () => _loadStock(withSummary: true),
            child: RefreshIndicator(
              onRefresh: () => _loadStock(page: _stockPage, withSummary: true),
              child: RepaintBoundary(
                key: _stockPngKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(mobile ? 8 : 12, 8, mobile ? 8 : 12, 16),
                  children: [
                    _stockInsight(),
                    if (_stockFilter != null || _search(_stockSearchCtrl) != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text(
                          tr('${SboxFmt.number(_stockTotal)} mặt hàng trong bộ lọc · giá trị ${SboxFmt.money(_stockFilteredValue)}'),
                          style: SboxType.smallStyle(SboxColors.textMuted),
                        ),
                      ),
                    SboxCard(
                      padding: EdgeInsets.zero,
                      child: SboxDataTable<Map<String, dynamic>>(
                        rows: _stockProducts,
                        paginate: false,
                        onRowTap: (p) => PosReportOpen.productDetail(context, '${p['id'] ?? p['productId'] ?? ''}'),
                        emptyTitle: 'Không có hàng trong bộ lọc',
                        columns: [
                          SboxColumn(
                            label: 'Hàng hóa',
                            primary: true,
                            flex: 3,
                            minWidth: 220,
                            cell: (p) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text('${p['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                              Text(
                                [p['productCode'], p['categoryName']]
                                    .where((x) => '${x ?? ''}'.trim().isNotEmpty)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SboxType.smallStyle(SboxColors.textMuted),
                              ),
                            ]),
                          ),
                          SboxColumn(
                            label: 'Tồn',
                            numeric: true,
                            minWidth: 100,
                            cell: (p) {
                              final q = _num(p['onHandQty']);
                              final unit = '${p['baseUnitName'] ?? ''}'.trim();
                              return Text('${qty(q)}${unit.isEmpty ? '' : ' $unit'}',
                                  textAlign: TextAlign.right,
                                  style: q <= 0 ? SboxType.bodyStyle(SboxColors.dangerText) : SboxType.bodyStyle());
                            },
                          ),
                          SboxColumn(
                            label: 'Tối thiểu / tối đa',
                            numeric: true,
                            minWidth: 120,
                            hideOnMobile: true,
                            text: (p) {
                              final mn = _num(p['minStockQty']), mx = _num(p['maxStockQty']);
                              if (mn <= 0 && mx <= 0) return '—';
                              return '${mn > 0 ? qty(mn) : '—'} / ${mx > 0 ? qty(mx) : '—'}';
                            },
                          ),
                          SboxColumn(label: 'Giá vốn', numeric: true, minWidth: 110, hideOnMobile: true,
                              text: (p) => SboxFmt.money(_num(p['costPrice']))),
                          SboxColumn(label: 'Giá trị tồn', numeric: true, minWidth: 130,
                              text: (p) => SboxFmt.money(_num(p['stockValue']))),
                          SboxColumn(
                            label: 'Tình trạng',
                            minWidth: 120,
                            cell: (p) => Align(
                              alignment: Alignment.centerLeft,
                              child: SboxStatusChip(
                                label: _stockStatusLabel('${p['status']}'),
                                tone: _stockStatusTone('${p['status']}'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _reportPager(page: _stockPage, pages: totalPages, total: _stockTotal, label: 'mặt hàng', onPage: (p) => _loadStock(page: p)),
      ],
    );
  }

  Widget _stockInsight() {
    final sm = _stockSummary ?? const <String, dynamic>{};
    final skus = _num(sm['totalSkus']);
    final out = _num(sm['outOfStock']);
    final below = _num(sm['belowMin']);
    final above = _num(sm['aboveMax']);
    final ok = sm.containsKey('okCount') ? _num(sm['okCount']) : (skus - out - below - above).clamp(0, double.infinity).toDouble();
    final negative = _num(sm['negativeCount']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: SboxInsightPanel(
        kpis: [
          SboxKpi(
            label: 'Giá trị tồn kho',
            value: SboxFmt.money(_num(sm['inventoryValue'])),
            icon: Icons.warehouse_outlined,
            note: '${SboxFmt.number(skus)} mặt hàng · tồn ${_fq(_num(sm['totalQty']))}',
            onTap: () => _setStockFilter(null),
          ),
          // Bấm ô KPI = lọc đúng nhóm đó; số trên ô và số dòng sau khi lọc luôn bằng nhau.
          SboxKpi(label: 'Hết hàng', value: SboxFmt.number(out), icon: Icons.remove_shopping_cart_outlined, tone: SboxTone.danger,
              note: negative > 0 ? '${SboxFmt.number(negative)} mã tồn âm — cần kiểm kho' : 'Tồn ≤ 0',
              onTap: () => _setStockFilter('OutOfStock')),
          SboxKpi(label: 'Dưới tồn tối thiểu', value: SboxFmt.number(below), icon: Icons.inventory_outlined, tone: SboxTone.warning,
              note: 'Còn hàng nhưng dưới mức tối thiểu', onTap: () => _setStockFilter('BelowMin')),
          SboxKpi(label: 'Vượt tồn tối đa', value: SboxFmt.number(above), icon: Icons.move_down_outlined, tone: SboxTone.violet,
              note: 'Đọng vốn — cân nhắc giảm nhập', onTap: () => _setStockFilter('AboveMax')),
        ],
        charts: [
          SboxChartCard(
            title: 'Tình trạng tồn kho',
            child: SboxDonutChart(
              valueFormat: (v) => '${SboxFmt.number(v)} mã',
              centerValue: SboxFmt.number(skus),
              centerLabel: 'mặt hàng',
              slices: [
                SboxSlice('Đủ hàng', ok, color: SboxColors.success),
                SboxSlice('Dưới tối thiểu', below, color: SboxColors.warning),
                SboxSlice('Hết hàng', out, color: SboxColors.danger),
                SboxSlice('Vượt tối đa', above, color: SboxColors.violet),
              ],
            ),
          ),
          SboxChartCard(
            title: 'Giá trị tồn lớn nhất',
            subtitle: 'Toàn bộ kho',
            child: SboxRankList(
              color: SboxColors.violet,
              items: [
                for (final p in _stockTopValue)
                  SboxSlice(p['name']?.toString() ?? '—', _num(p['stockValue']),
                      caption: 'Tồn ${_fq(_num(p['onHandQty']))} ${p['baseUnitName'] ?? ''}'.trim()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setLotFilter(String f) {
    setState(() => _lotFilter = f);
    _loadLots();
  }

  Widget _lotInsight() {
    final sm = _lotSummary ?? const <String, dynamic>{};
    final active = _num(sm['activeLotCount']);
    final soon = _num(sm['expiringSoonLotCount']);
    final expired = _num(sm['expiredLotCount']);
    final noExp = _num(sm['noExpiryLotCount']);
    final ok = sm.containsKey('okLotCount') ? _num(sm['okLotCount']) : (active - soon - expired - noExp).clamp(0, double.infinity).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: SboxInsightPanel(
        kpis: [
          SboxKpi(label: 'Đã hết hạn', value: SboxFmt.number(expired), icon: Icons.dangerous_outlined, tone: SboxTone.danger,
              note: '${SboxFmt.money(_num(sm['expiredValue']))} · cần hủy / xử lý', onTap: () => _setLotFilter('expired')),
          SboxKpi(label: 'Sắp hết hạn', value: SboxFmt.number(soon), icon: Icons.event_busy_outlined, tone: SboxTone.warning,
              note: '${SboxFmt.money(_num(sm['expiringSoonValue']))} · ưu tiên bán trước', onTap: () => _setLotFilter('expiring')),
          SboxKpi(label: 'Lô đang còn hàng', value: SboxFmt.number(active), icon: Icons.layers_outlined, tone: SboxTone.violet,
              note: 'SL ${_fq(_num(sm['totalLotQty']))}', onTap: () => _setLotFilter('all')),
          SboxKpi(label: 'Giá trị hàng theo lô', value: SboxFmt.money(_num(sm['lotInventoryValue'])), icon: Icons.inventory_2_outlined,
              note: noExp > 0 ? '${SboxFmt.number(noExp)} lô không ghi HSD' : null),
        ],
        charts: [
          SboxChartCard(
            title: 'Tình trạng hạn dùng',
            child: SboxDonutChart(
              valueFormat: (v) => '${SboxFmt.number(v)} lô',
              centerValue: SboxFmt.number(active),
              centerLabel: 'lô',
              slices: [
                SboxSlice('Còn hạn', ok, color: SboxColors.success),
                SboxSlice('Sắp hết hạn', soon, color: SboxColors.warning),
                SboxSlice('Đã hết hạn', expired, color: SboxColors.danger),
                SboxSlice('Không ghi HSD', noExp, color: SboxColors.slate400),
              ],
            ),
          ),
          SboxChartCard(
            title: 'Lô rủi ro giá trị lớn',
            subtitle: 'Sắp hết / đã hết hạn trong danh sách đang xem',
            child: SboxRankList(
              color: SboxColors.danger,
              items: [
                for (final l in [..._lotItems]..sort((a, b) => _num(b['stockValue']).compareTo(_num(a['stockValue']))))
                  if ('${l['status']}' == 'expired' || '${l['status']}' == 'expiring')
                    SboxSlice('${l['productName'] ?? ''}${(l['lotNo'] ?? '').toString().isEmpty ? '' : ' · ${l['lotNo']}'}',
                        _num(l['stockValue']),
                        caption: _lotDaysLabel(l['daysUntilExpiry'])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _lotDaysLabel(dynamic days) {
    final d = days is num ? days.toInt() : int.tryParse('${days ?? ''}');
    if (d == null) return '—';
    if (d < 0) return 'Quá hạn ${-d} ngày';
    if (d == 0) return 'Hết hạn hôm nay';
    return 'Còn $d ngày';
  }

  /// Hạn dùng theo lô: cùng khuôn với Tồn kho.
  Widget _buildLotsTab(bool canExport) {
    final totalPages = (_lotTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    final dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');
    String date(dynamic raw) {
      final d = raw == null ? null : DateTime.tryParse('$raw');
      return d == null ? '—' : dateFmt.format(d);
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 4),
          child: SboxFilterBar(
            searchHint: 'Tìm hàng / mã lô / mã vạch',
            searchController: _lotSearchCtrl,
            onSearch: (v) => _onStockSearch(v, () => _loadLots()),
            filters: [
              SboxFilterChip<String>(
                label: 'Hạn dùng',
                value: _lotFilter,
                options: _lotFilterOptions,
                onChanged: _setLotFilter,
              ),
            ],
            actions: [
              if (canExport)
                _exportButtons(
                  onExcel: _exporting ? null : _exportLots,
                  onPng: () => PosReportExport.png(context: context, key: _lotPngKey, filePrefix: 'POS_LoHSD'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _reportBody(
            loading: _loadingLots,
            hasData: _lotSummary != null || _lotItems.isNotEmpty,
            error: _lotError,
            onRetry: () => _loadLots(withSummary: true),
            child: RefreshIndicator(
              onRefresh: () => _loadLots(page: _lotPage, withSummary: true),
              child: RepaintBoundary(
                key: _lotPngKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(mobile ? 8 : 12, 8, mobile ? 8 : 12, 16),
                  children: [
                    _lotInsight(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        tr('${_lotFilterOptions[_lotFilter]}: ${SboxFmt.number(_lotTotal)} lô · giá trị ${SboxFmt.money(_lotFilteredValue)}'),
                        style: SboxType.smallStyle(SboxColors.textMuted),
                      ),
                    ),
                    SboxCard(
                      padding: EdgeInsets.zero,
                      child: SboxDataTable<Map<String, dynamic>>(
                        rows: _lotItems,
                        paginate: false,
                        onRowTap: (l) => PosReportOpen.productDetail(context, '${l['productId'] ?? l['ProductId'] ?? ''}'),
                        emptyTitle: _lotFilter == 'attention'
                            ? 'Không có lô nào hết hạn hoặc sắp hết hạn'
                            : 'Không có lô trong bộ lọc',
                        columns: [
                          SboxColumn(
                            label: 'Hàng / lô',
                            primary: true,
                            flex: 3,
                            minWidth: 220,
                            cell: (l) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text('${l['productName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                              Text(
                                [
                                  l['productCode'],
                                  if ('${l['lotNo'] ?? ''}'.isNotEmpty) 'Lô ${l['lotNo']}',
                                ].where((x) => '${x ?? ''}'.trim().isNotEmpty).join(' · '),
                                style: SboxType.smallStyle(SboxColors.textMuted),
                              ),
                            ]),
                          ),
                          SboxColumn(label: 'HSD', minWidth: 110, text: (l) => date(l['expiryDate'])),
                          SboxColumn(
                            label: 'Còn lại',
                            minWidth: 130,
                            cell: (l) {
                              final d = l['daysUntilExpiry'];
                              final n = d is num ? d.toInt() : null;
                              return Text(_lotDaysLabel(d),
                                  style: n != null && n < 0 ? SboxType.bodyStyle(SboxColors.dangerText) : SboxType.bodyStyle());
                            },
                          ),
                          SboxColumn(label: 'SL', numeric: true, minWidth: 90, text: (l) {
                            final unit = '${l['unitName'] ?? ''}'.trim();
                            return '${_fq(_num(l['qtyOnHand']))}${unit.isEmpty ? '' : ' $unit'}';
                          }),
                          SboxColumn(label: 'Giá trị', numeric: true, minWidth: 120,
                              text: (l) => SboxFmt.money(_num(l['stockValue']))),
                          SboxColumn(
                            label: 'Trạng thái',
                            minWidth: 110,
                            cell: (l) => Align(
                              alignment: Alignment.centerLeft,
                              child: SboxStatusChip(label: _lotStatusLabel('${l['status']}'), tone: _lotStatusTone('${l['status']}')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _reportPager(page: _lotPage, pages: totalPages, total: _lotTotal, label: 'lô', onPage: (p) => _loadLots(page: p)),
      ],
    );
  }

  String _fmtDay(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse('$v');
    if (d == null) return '$v';
    return DateFormat('dd/MM').format(d);
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(tr(label), style: onTap == null ? null : const TextStyle(color: PosTheme.kiotBlue))),
              Text(tr(value), style: const TextStyle(fontWeight: FontWeight.w500)),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: PosTheme.textSecondary),
            ],
          ),
        ),
      );

}
