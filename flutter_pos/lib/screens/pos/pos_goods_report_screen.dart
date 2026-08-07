import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_goods_filter_sheet.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';

/// Báo cáo hàng hóa kiểu KiotViet — top doanh thu, tồn kho, top giá trị kho.
class PosGoodsReportScreen extends StatefulWidget {
  const PosGoodsReportScreen({super.key});

  @override
  State<PosGoodsReportScreen> createState() => _PosGoodsReportScreenState();
}

class _PosGoodsReportScreenState extends State<PosGoodsReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

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
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _data = null;
      }
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
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  String _productLabel(Map<String, dynamic> p) {
    final name = p['productName']?.toString() ?? p['name']?.toString() ?? '—';
    final unit = p['baseUnitName']?.toString();
    if (unit != null && unit.isNotEmpty) return '$name ($unit)';
    return name;
  }

  List<Map<String, dynamic>> _applyStockFilter(List<Map<String, dynamic>> items) {
    return items.where((p) {
      final qty = _num(p['onHandQty']);
      final min = _num(p['minStockQty']);
      switch (_filter.inventoryStatus) {
        case PosGoodsInventoryFilter.belowMin:
          return min > 0 && qty < min && qty > 0;
        case PosGoodsInventoryFilter.aboveMin:
          return min > 0 && qty > min;
        case PosGoodsInventoryFilter.inStock:
          return qty > 0;
        case PosGoodsInventoryFilter.outOfStock:
          return qty <= 0;
        case PosGoodsInventoryFilter.all:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryValue = _num(_data?['inventoryValue'] ?? _data?['totalStockValue']);
    final productCount =
        (_data?['productCount'] as num?)?.toInt() ?? (_data?['totalSkus'] as num?)?.toInt() ?? 0;

    final topRevenue = ((_data?['topByRevenue'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final topStock = _applyStockFilter(
      ((_data?['topByStockValue'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );

    return PosReportMobileScaffold(
      title: 'Báo cáo hàng hóa',
      time: _time,
      onTimeChanged: (PosKiotTimeFilterState s) async {
        setState(() => _time = s);
        await _load();
      },
      onFilterTap: _openFilter,
      onRefresh: _load,
      body: _loading
          ? ListView(
              children: const [
                SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(color: PosTheme.kiotBlue),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Top hàng theo doanh thu',
                  trailing: const Icon(Icons.swap_vert, size: 18, color: PosTheme.textSecondary),
                  child: PosReportRankList(
                    items: topRevenue,
                    labelOf: _productLabel,
                    valueOf: (p) => _num(p['revenue']),
                    moneyFmt: _moneyFmt,
                    allowNegative: true,
                  ),
                ),
                PosReportInventoryBanner(
                  inventoryValue: inventoryValue,
                  productCount: productCount,
                  moneyFmt: _moneyFmt,
                ),
                PosReportCard(
                  title: 'Top hàng theo giá trị kho',
                  trailing: const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
                  child: PosReportRankList(
                    items: topStock,
                    labelOf: _productLabel,
                    valueOf: (p) => _num(p['stockValue']),
                    moneyFmt: _moneyFmt,
                  ),
                ),
              ],
            ),
    );
  }
}
