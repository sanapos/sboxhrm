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

const _kiotBlue = PosTheme.kiotBlue;

/// Báo cáo POS: doanh thu + tồn kho (API `/api/pos/reports/*`).
class PosReportsScreen extends StatefulWidget {
  const PosReportsScreen({super.key});

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
  List<Map<String, dynamic>> _stockProducts = [];
  int _stockTotal = 0;
  int _stockPage = 1;
  static const _stockPageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSales();
    _loadStock();
  }

  @override
  void dispose() {
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
            .showSuccess(title: 'Xuất file', message: 'Đã xuất Excel doanh thu');
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
            .showSuccess(title: 'Xuất file', message: 'Đã xuất Excel tồn kho');
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
      return const Scaffold(body: Center(child: Text('Không có quyền xem báo cáo POS')));
    }
    final canExport = perm.canExport('PosSalesReport') || perm.canExport('PosProducts');
    final mobile = posUseMobileList(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosModuleToolbar(activeModule: 'PosSalesReport'),
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              labelColor: _kiotBlue,
              indicatorColor: _kiotBlue,
              isScrollable: mobile,
              tabAlignment: mobile ? TabAlignment.start : TabAlignment.fill,
              tabs: [
                Tab(text: mobile ? 'Doanh thu' : 'Doanh thu bán hàng'),
                const Tab(text: 'Tồn kho'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildSalesTab(canExport),
                _buildStockTab(canExport),
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
                        label: const Text('Xuất Excel'),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: PosKiotTimeFilter(
                        state: _salesTime,
                        onChanged: (s) {
                          setState(() => _salesTime = s);
                          _loadSales();
                        },
                      ),
                    ),
                    if (canExport)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                        onPressed: _exporting ? null : _exportSales,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Excel'),
                      ),
                  ],
                ),
        ),
        Expanded(
          child: _loadingSales
              ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
              : _salesSummary == null
                  ? const Center(child: Text('Không có dữ liệu'))
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
          _row('Doanh thu', _moneyFmt.format(_num(s['totalRevenue']))),
          _row('Đã thu', _moneyFmt.format(_num(s['totalPaid']))),
          _row('Giảm giá', _moneyFmt.format(_num(s['totalDiscount']))),
        ]),
        const SizedBox(height: 12),
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
                      decoration: const InputDecoration(
                        hintText: 'Tìm hàng hóa',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadStock(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: _kiotBlue),
                            onPressed: _loadingStock ? null : () => _loadStock(),
                            child: const Text('Lọc'),
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
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _stockSearchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Tìm hàng hóa',
                          prefixIcon: Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _loadStock(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                      onPressed: _loadingStock ? null : () => _loadStock(),
                      child: const Text('Lọc'),
                    ),
                    if (canExport) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : _exportStock,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Excel'),
                      ),
                    ],
                  ],
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
                          title: Text(p['name']?.toString() ?? ''),
                          subtitle: Text(
                              '${p['productCode']} · Tồn: ${p['onHandQty']}'),
                          trailing: Text(
                            _moneyFmt.format(_num(p['stockValue'])),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }
                    return ListTile(
                      title: Text(p['name']?.toString() ?? ''),
                      subtitle: Text(
                          '${p['productCode']} · Tồn: ${p['onHandQty']}'),
                      trailing: Text(_moneyFmt.format(_num(p['stockValue']))),
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
                Text('$_stockPage / $totalPages'),
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

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _chip(String label, String value) => Chip(
        label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      );
}
