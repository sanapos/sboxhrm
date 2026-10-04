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
  final _stockSearchCtrl = TextEditingController();
  final _salesPngKey = GlobalKey();
  final _stockPngKey = GlobalKey();
  final _lotPngKey = GlobalKey();

  late final TabController _tabs;
  PosKiotTimeFilterState _salesTime = PosKiotTimeFilterState.thisMonth();
  bool _loadingSales = false;
  bool _loadingStock = false;
  bool _exporting = false;
  Map<String, dynamic>? _salesSummary;
  Map<String, dynamic>? _stockSummary;
  Map<String, dynamic>? _lotSummary;
  List<Map<String, dynamic>> _stockProducts = [];
  List<Map<String, dynamic>> _lotItems = [];
  int _stockTotal = 0;
  int _lotTotal = 0;
  int _stockPage = 1;
  int _lotPage = 1;
  String? _lotFilter;
  String? _stockFilter;
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
        if (_stockSummary == null && !_loadingStock) unawaited(_loadStock());
        break;
      case 2:
        if (_lotSummary == null && !_loadingStock) unawaited(_loadLots());
        break;
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _stockDebounce?.cancel();
    _stockSearchCtrl.dispose();
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

  Future<void> _loadStock({int page = 1}) async {
    setState(() => _loadingStock = true);
    final sumRes = await _api.getPosStockReportSummary();
    final listRes = await _api.getPosStockReportProducts(
      search: _stockSearchCtrl.text.trim().isEmpty ? null : _stockSearchCtrl.text.trim(),
      filter: _stockFilter,
      page: page,
      pageSize: _stockPageSize,
    );
    if (!mounted) return;
    setState(() {
      _loadingStock = false;
      _stockPage = page;
      if (sumRes['isSuccess'] == true && sumRes['data'] is Map) {
        _stockSummary = Map<String, dynamic>.from(sumRes['data'] as Map);
      }
      if (listRes['isSuccess'] == true && listRes['data'] is Map) {
        final data = listRes['data'] as Map;
        _stockTotal = (data['total'] as num?)?.toInt() ?? 0;
        _stockProducts = ((data['items'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    });
  }

  Future<void> _loadLots({int page = 1}) async {
    setState(() => _loadingStock = true);
    final sumRes = await _api.getPosStockLotReportSummary();
    final listRes = await _api.getPosStockLotReport(
      search: _stockSearchCtrl.text.trim().isEmpty ? null : _stockSearchCtrl.text.trim(),
      filter: _lotFilter,
      page: page,
      pageSize: _stockPageSize,
    );
    if (!mounted) return;
    setState(() {
      _loadingStock = false;
      _lotPage = page;
      if (sumRes['isSuccess'] == true && sumRes['data'] is Map) {
        _lotSummary = Map<String, dynamic>.from(sumRes['data'] as Map);
      }
      if (listRes['isSuccess'] == true && listRes['data'] is Map) {
        final data = listRes['data'] as Map;
        _lotTotal = (data['total'] as num?)?.toInt() ?? 0;
        _lotItems = ((data['items'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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
      final res = await _api.exportPosStockReportExcel(
        search: _stockSearchCtrl.text.trim().isEmpty ? null : _stockSearchCtrl.text.trim(),
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

  Future<void> _exportLots() async {
    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo lô / HSD',
      sheetName: 'Lo HSD',
      filePrefix: 'POS_LoHSD',
      filterLabel: _lotFilter,
      headers: const ['Hàng hóa', 'Lô', 'HSD', 'SL', 'Giá trị', 'Trạng thái'],
      rows: [
        for (final l in _lotItems)
          [
            l['productName'] ?? '',
            l['lotNo'] ?? '',
            l['expiryDate'] ?? l['ExpiryDate'] ?? '',
            l['qtyOnHand'] ?? l['QtyOnHand'] ?? '',
            _num(l['stockValue'] ?? l['StockValue']),
            l['status'] ?? '',
          ],
      ],
    );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canView = perm.canView('PosSalesReport') || perm.canView('PosProducts');
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Báo cáo POS'))),
        body: Center(child: Text(tr('Không có quyền xem báo cáo POS'))),
      );
    }
    final canExport = perm.canExport('PosSalesReport') || perm.canExport('PosProducts');
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
                    1 => _buildStockTab(canExport),
                    2 => _buildLotsTab(),
                    _ => _buildSalesTab(canExport),
                  }
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildSalesTab(canExport),
                      _buildStockTab(canExport),
                      _buildLotsTab(),
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
                ),
          ]),
        if (((s['byDay'] as List?) ?? []).isNotEmpty) const SizedBox(height: 12),
        if (((s['topEmployees'] as List?) ?? []).isNotEmpty)
          _card('Top nhân viên', [
            for (final e in (s['topEmployees'] as List).take(10))
              if (e is Map)
                _row(
                  (e['soldBy']?.toString().trim().isNotEmpty == true)
                      ? e['soldBy'].toString()
                      : '—',
                  '${_moneyFmt.format(_num(e['revenue']))} (${e['orderCount'] ?? 0})',
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

  /// Tồn kho: một hàng lọc kiểu HRM (tìm · tình trạng · Excel/PNG), số liệu + bảng — không còn nút «Lọc» và hàng chip tổng lặp số liệu.
  Widget _buildStockTab(bool canExport) {
    final totalPages = (_stockTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 4),
          child: SboxFilterBar(
            searchHint: 'Tìm hàng hóa',
            searchController: _stockSearchCtrl,
            onSearch: (v) => _onStockSearch(v, () => _loadStock()),
            filters: [
              SboxFilterChip<String>(
                label: 'Tình trạng',
                value: _stockFilter ?? 'all',
                options: const {'all': 'Tất cả', 'BelowMin': 'Dưới tối thiểu', 'OutOfStock': 'Hết hàng', 'AboveMax': 'Vượt tối đa'},
                onChanged: (v) {
                  setState(() => _stockFilter = v == 'all' ? null : v);
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
          child: _loadingStock
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : RepaintBoundary(
                  key: _stockPngKey,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(mobile ? 8 : 12, 8, mobile ? 8 : 12, 16),
                    children: [
                      _stockInsight(),
                      SboxCard(
                        padding: EdgeInsets.zero,
                        child: SboxDataTable<Map<String, dynamic>>(
                          rows: _stockProducts.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                          paginate: false,
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
                                Text('${p['productCode'] ?? ''}', style: SboxType.smallStyle(SboxColors.textMuted)),
                              ]),
                            ),
                            SboxColumn(
                              label: 'Tồn',
                              numeric: true,
                              minWidth: 90,
                              cell: (p) {
                                final q = _num(p['onHandQty']);
                                return Text(SboxFmt.number(q),
                                    textAlign: TextAlign.right,
                                    style: q <= 0 ? SboxType.bodyStyle(SboxColors.dangerText) : SboxType.bodyStyle());
                              },
                              sortValue: (p) => _num(p['onHandQty']),
                            ),
                            SboxColumn(label: 'Giá trị tồn', numeric: true, minWidth: 130,
                                text: (p) => SboxFmt.money(_num(p['stockValue'])), sortValue: (p) => _num(p['stockValue'])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        _reportPager(page: _stockPage, pages: totalPages, total: _stockTotal, label: 'SKU', onPage: (p) => _loadStock(page: p)),
      ],
    );
  }

  Widget _stockInsight() {
    final sm = _stockSummary ?? const <String, dynamic>{};
    final skus = _num(sm['totalSkus']);
    final out = _num(sm['outOfStock']);
    final below = _num(sm['belowMin']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: SboxInsightPanel(
        kpis: [
          SboxKpi(label: 'Giá trị tồn kho', value: SboxFmt.money(_num(sm['inventoryValue'])), icon: Icons.warehouse_outlined),
          SboxKpi(label: 'Mặt hàng (SKU)', value: SboxFmt.number(skus), icon: Icons.category_outlined, tone: SboxTone.violet,
              note: 'Tổng tồn ${SboxFmt.number(_num(sm['totalQty']))}'),
          SboxKpi(label: 'Hết hàng', value: SboxFmt.number(out), icon: Icons.remove_shopping_cart_outlined, tone: SboxTone.danger),
          SboxKpi(label: 'Dưới tồn tối thiểu', value: SboxFmt.number(below), icon: Icons.inventory_outlined, tone: SboxTone.warning, note: 'Cần nhập thêm'),
        ],
        charts: [
          SboxChartCard(
            title: 'Tình trạng tồn kho',
            child: SboxDonutChart(
              valueFormat: (v) => '${SboxFmt.number(v)} mã',
              centerValue: SboxFmt.number(skus),
              centerLabel: 'mặt hàng',
              slices: [
                SboxSlice('Đủ hàng', (skus - out - below).clamp(0, double.infinity).toDouble(), color: SboxColors.success),
                SboxSlice('Dưới tối thiểu', below, color: SboxColors.warning),
                SboxSlice('Hết hàng', out, color: SboxColors.danger),
              ],
            ),
          ),
          SboxChartCard(
            title: 'Giá trị tồn lớn nhất',
            subtitle: 'Trong trang đang xem',
            child: SboxRankList(
              color: SboxColors.violet,
              items: [
                for (final p in _stockProducts)
                  SboxSlice(p['name']?.toString() ?? '—', _num(p['stockValue']), caption: 'Tồn ${p['onHandQty'] ?? 0}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lotInsight() {
    final sm = _lotSummary ?? const <String, dynamic>{};
    final active = _num(sm['activeLotCount']);
    final soon = _num(sm['expiringSoonLotCount']);
    final expired = _num(sm['expiredLotCount']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: SboxInsightPanel(
        kpis: [
          SboxKpi(label: 'Giá trị hàng theo lô', value: SboxFmt.money(_num(sm['lotInventoryValue'])), icon: Icons.inventory_2_outlined),
          SboxKpi(label: 'Lô đang còn hàng', value: SboxFmt.number(active), icon: Icons.layers_outlined, tone: SboxTone.violet,
              note: 'SL ${SboxFmt.number(_num(sm['totalLotQty']))}'),
          SboxKpi(label: 'Sắp hết hạn', value: SboxFmt.number(soon), icon: Icons.event_busy_outlined, tone: SboxTone.warning, note: 'Ưu tiên bán trước'),
          SboxKpi(label: 'Đã hết hạn', value: SboxFmt.number(expired), icon: Icons.dangerous_outlined, tone: SboxTone.danger, note: 'Cần hủy / xử lý'),
        ],
        charts: [
          SboxChartCard(
            title: 'Tình trạng hạn dùng',
            child: SboxDonutChart(
              valueFormat: (v) => '${SboxFmt.number(v)} lô',
              centerValue: SboxFmt.number(active),
              centerLabel: 'lô',
              slices: [
                SboxSlice('Còn hạn', (active - soon - expired).clamp(0, double.infinity).toDouble(), color: SboxColors.success),
                SboxSlice('Sắp hết hạn', soon, color: SboxColors.warning),
                SboxSlice('Đã hết hạn', expired, color: SboxColors.danger),
              ],
            ),
          ),
          SboxChartCard(
            title: 'Lô rủi ro giá trị lớn',
            subtitle: 'Sắp hết / đã hết hạn trong trang',
            child: SboxRankList(
              color: SboxColors.danger,
              items: [
                for (final l in _lotItems)
                  if ('${l['status']}' == 'expired' || '${l['status']}' == 'expiring')
                    SboxSlice('${l['productName'] ?? ''}${(l['lotNo'] ?? '').toString().isEmpty ? '' : ' · ${l['lotNo']}'}',
                        _num(l['stockValue'] ?? l['StockValue']),
                        caption: '${l['daysUntilExpiry'] ?? ''} ngày'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hạn dùng theo lô: cùng khuôn với Tồn kho.
  Widget _buildLotsTab() {
    final totalPages = (_lotTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    final dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

    SboxTone statusTone(String? status) => switch (status) {
          'expired' => SboxTone.danger,
          'expiring' => SboxTone.warning,
          _ => SboxTone.success,
        };

    String statusLabel(String? status) => switch (status) {
          'expired' => 'Hết HSD',
          'expiring' => 'Sắp hết',
          _ => 'Còn hạn',
        };

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 4),
          child: SboxFilterBar(
            searchHint: 'Tìm hàng / mã lô',
            searchController: _stockSearchCtrl,
            onSearch: (v) => _onStockSearch(v, () => _loadLots()),
            filters: [
              SboxFilterChip<String>(
                label: 'Hạn dùng',
                value: _lotFilter ?? 'all',
                options: const {'all': 'Tất cả', 'expiring': 'Sắp hết HSD', 'expired': 'Đã hết HSD'},
                onChanged: (v) {
                  setState(() => _lotFilter = v == 'all' ? null : v);
                  _loadLots();
                },
              ),
            ],
            actions: [
              _exportButtons(
                onExcel: _exportLots,
                onPng: () => PosReportExport.png(context: context, key: _lotPngKey, filePrefix: 'POS_LoHSD'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingStock
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : RepaintBoundary(
                  key: _lotPngKey,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(mobile ? 8 : 12, 8, mobile ? 8 : 12, 16),
                    children: [
                      _lotInsight(),
                      SboxCard(
                        padding: EdgeInsets.zero,
                        child: SboxDataTable<Map<String, dynamic>>(
                          rows: _lotItems.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                          paginate: false,
                          emptyTitle: 'Chưa có lô hàng theo dõi hạn dùng',
                          columns: [
                            SboxColumn(
                              label: 'Hàng / lô',
                              primary: true,
                              flex: 3,
                              minWidth: 220,
                              cell: (l) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text('${l['productName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                                if ('${l['lotNo'] ?? ''}'.isNotEmpty)
                                  Text('Lô ${l['lotNo']}', style: SboxType.smallStyle(SboxColors.textMuted)),
                              ]),
                            ),
                            SboxColumn(
                              label: 'HSD',
                              minWidth: 110,
                              text: (l) {
                                final raw = l['expiryDate'] ?? l['ExpiryDate'];
                                final d = raw == null ? null : DateTime.tryParse('$raw')?.toLocal();
                                return d == null ? '—' : dateFmt.format(d);
                              },
                            ),
                            SboxColumn(label: 'Còn (ngày)', numeric: true, minWidth: 90, hideOnMobile: true,
                                text: (l) => '${l['daysUntilExpiry'] ?? l['DaysUntilExpiry'] ?? '—'}'),
                            SboxColumn(label: 'SL', numeric: true, minWidth: 80,
                                text: (l) => SboxFmt.number(_num(l['qtyOnHand'] ?? l['QtyOnHand']))),
                            SboxColumn(label: 'Giá trị', numeric: true, minWidth: 120,
                                text: (l) => SboxFmt.money(_num(l['stockValue'] ?? l['StockValue']))),
                            SboxColumn(
                              label: 'Trạng thái',
                              minWidth: 110,
                              cell: (l) => Align(
                                alignment: Alignment.centerLeft,
                                child: SboxStatusChip(label: statusLabel('${l['status']}'), tone: statusTone('${l['status']}')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        _reportPager(page: _lotPage, pages: totalPages, total: _lotTotal, label: 'Lô', onPage: (p) => _loadLots(page: p)),
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(tr(label))),
            Text(tr(value), style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

}
