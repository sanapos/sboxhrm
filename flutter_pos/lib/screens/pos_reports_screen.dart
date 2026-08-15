import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canView = perm.canView('PosSalesReport') || perm.canView('PosProducts');
    if (!canView) {
      return Scaffold(body: Center(child: Text(tr('Không có quyền xem báo cáo POS'))));
    }
    final canExport = perm.canExport('PosSalesReport') || perm.canExport('PosProducts');
    final mobile = posUseMobileList(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.lockTab)
            PosMobileKiotHeader(
              title: switch (widget.initialTab) {
                1 => 'Tồn kho',
                2 => 'Hàng sắp hết hạn',
                _ => 'Doanh thu',
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
              ? Column(
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
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                        onPressed: _exporting ? null : _exportSales,
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(tr('Xuất Excel')),
                      ),
                    ],
                  ],
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
                  : _buildSalesBody(_salesSummary!),
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

  Widget _buildStockTab(bool canExport) {
    final totalPages = (_stockTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _stockSearchCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Tìm hàng hóa'),
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadStock(),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text(tr('Tất cả')),
                          selected: _stockFilter == null,
                          onSelected: (_) {
                            setState(() => _stockFilter = null);
                            _loadStock();
                          },
                        ),
                        FilterChip(
                          label: Text(tr('Dưới min')),
                          selected: _stockFilter == 'BelowMin',
                          onSelected: (_) {
                            setState(() => _stockFilter = 'BelowMin');
                            _loadStock();
                          },
                        ),
                        FilterChip(
                          label: Text(tr('Hết hàng')),
                          selected: _stockFilter == 'OutOfStock',
                          onSelected: (_) {
                            setState(() => _stockFilter = 'OutOfStock');
                            _loadStock();
                          },
                        ),
                        FilterChip(
                          label: Text(tr('Trên max')),
                          selected: _stockFilter == 'AboveMax',
                          onSelected: (_) {
                            setState(() => _stockFilter = 'AboveMax');
                            _loadStock();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: _kiotBlue),
                            onPressed: _loadingStock ? null : () => _loadStock(),
                            child: Text(tr('Lọc')),
                          ),
                        ),
                        if (canExport) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _exporting ? null : _exportStock,
                            child: const Icon(Icons.download),
                          ),
                        ],
                      ],
                    ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 360,
                        child: TextField(
                          controller: _stockSearchCtrl,
                          decoration: InputDecoration(
                            hintText: tr('Tìm hàng hóa'),
                            prefixIcon: Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _loadStock(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style:
                            FilledButton.styleFrom(backgroundColor: _kiotBlue),
                        onPressed:
                            _loadingStock ? null : () => _loadStock(),
                        child: Text(tr('Lọc')),
                      ),
                      if (canExport) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : _exportStock,
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(tr('Excel')),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        if (_stockSummary != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _chip('SKU', '${_stockSummary!['totalSkus'] ?? 0}'),
                _chip('Tồn', '${_stockSummary!['totalQty'] ?? 0}'),
                _chip('Giá trị', _moneyFmt.format(_num(_stockSummary!['inventoryValue']))),
                _chip('Hết hàng', '${_stockSummary!['outOfStock'] ?? 0}'),
              ],
            ),
          ),
        Expanded(
          child: _loadingStock
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _stockProducts.length,
                  itemBuilder: (_, i) {
                    final p = _stockProducts[i];
                    if (mobile) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: PosTheme.mobileCardDecoration(),
                        child: ListTile(
                          title: Text(tr(p['name']?.toString() ?? '')),
                          subtitle: Text(
                              tr('${p['productCode']} · Tồn: ${p['onHandQty']}')),
                          trailing: Text(
                            tr(_moneyFmt.format(_num(p['stockValue']))),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }
                    return ListTile(
                      title: Text(tr(p['name']?.toString() ?? '')),
                      subtitle: Text(
                          tr('${p['productCode']} · Tồn: ${p['onHandQty']}')),
                      trailing: Text(tr(_moneyFmt.format(_num(p['stockValue'])))),
                    );
                  },
                ),
        ),
        if (totalPages > 1)
          mobile
              ? PosMobilePager(
                  total: _stockTotal,
                  page: _stockPage,
                  pageSize: _stockPageSize,
                  label: 'SKU',
                  onPageChanged: (p) => _loadStock(page: p),
                )
              : Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _stockPage > 1 ? () => _loadStock(page: _stockPage - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(tr('$_stockPage / $totalPages')),
                IconButton(
                  onPressed: _stockPage < totalPages
                      ? () => _loadStock(page: _stockPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLotsTab() {
    final totalPages = (_lotTotal / _stockPageSize).ceil().clamp(1, 9999);
    final mobile = posUseMobileList(context);
    final dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

    Color statusColor(String? status) => switch (status) {
          'expired' => const Color(0xFFEF4444),
          'expiring' => const Color(0xFFF59E0B),
          _ => const Color(0xFF64748B),
        };

    String statusLabel(String? status) => switch (status) {
          'expired' => 'Hết HSD',
          'expiring' => 'Sắp hết',
          _ => 'OK',
        };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _stockSearchCtrl,
                decoration: InputDecoration(
                  hintText: tr('Tìm hàng / mã lô'),
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _loadLots(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(tr('Tất cả')),
                    selected: _lotFilter == null,
                    onSelected: (_) {
                      setState(() => _lotFilter = null);
                      _loadLots();
                    },
                  ),
                  FilterChip(
                    label: Text(tr('Sắp hết HSD')),
                    selected: _lotFilter == 'expiring',
                    onSelected: (_) {
                      setState(() => _lotFilter = 'expiring');
                      _loadLots();
                    },
                  ),
                  FilterChip(
                    label: Text(tr('Đã hết HSD')),
                    selected: _lotFilter == 'expired',
                    onSelected: (_) {
                      setState(() => _lotFilter = 'expired');
                      _loadLots();
                    },
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                    onPressed: _loadingStock ? null : () => _loadLots(),
                    child: Text(tr('Lọc')),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_lotSummary != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _chip('Lô active', '${_lotSummary!['activeLotCount'] ?? 0}'),
                _chip('SL lô', '${_lotSummary!['totalLotQty'] ?? 0}'),
                _chip('Giá trị', _moneyFmt.format(_num(_lotSummary!['lotInventoryValue']))),
                _chip('Sắp hết', '${_lotSummary!['expiringSoonLotCount'] ?? 0}'),
                _chip('Hết HSD', '${_lotSummary!['expiredLotCount'] ?? 0}'),
              ],
            ),
          ),
        Expanded(
          child: _loadingStock
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _lotItems.length,
                  itemBuilder: (_, i) {
                    final l = _lotItems[i];
                    final status = l['status']?.toString();
                    final expiryRaw = l['expiryDate'] ?? l['ExpiryDate'];
                    final expiry = expiryRaw != null
                        ? DateTime.tryParse(expiryRaw.toString())?.toLocal()
                        : null;
                    final days = (l['daysUntilExpiry'] ?? l['DaysUntilExpiry'] as num?)?.toInt();
                    final subtitle = [
                      if (l['lotNo'] != null && l['lotNo'].toString().isNotEmpty)
                        'Lô: ${l['lotNo']}',
                      if (expiry != null) 'HSD: ${dateFmt.format(expiry)}',
                      if (days != null) 'Còn $days ngày',
                      'SL: ${l['qtyOnHand'] ?? l['QtyOnHand']}',
                    ].join(' · ');

                    final tile = ListTile(
                      title: Text(tr(l['productName']?.toString() ?? '')),
                      subtitle: Text(tr(subtitle)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            tr(_moneyFmt.format(_num(l['stockValue'] ?? l['StockValue']))),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            tr(statusLabel(status)),
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor(status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (mobile) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: PosTheme.mobileCardDecoration(),
                        child: tile,
                      );
                    }
                    return tile;
                  },
                ),
        ),
        if (totalPages > 1)
          mobile
              ? PosMobilePager(
                  total: _lotTotal,
                  page: _lotPage,
                  pageSize: _stockPageSize,
                  label: 'Lô',
                  onPageChanged: (p) => _loadLots(page: p),
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _lotPage > 1 ? () => _loadLots(page: _lotPage - 1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(tr('$_lotPage / $totalPages')),
                      IconButton(
                        onPressed: _lotPage < totalPages
                            ? () => _loadLots(page: _lotPage + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
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
            Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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

  Widget _chip(String label, String value) => Chip(
        label: Text(tr('$label: $value'), style: const TextStyle(fontSize: 12)),
      );
}
