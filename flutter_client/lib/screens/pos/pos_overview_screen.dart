import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_kiot_time_filter.dart';
import '../../widgets/pos/pos_theme.dart';

/// Tổng quan POS mobile — doanh thu, tồn kho, hàng bán chạy.
class PosOverviewScreen extends StatefulWidget {
  const PosOverviewScreen({super.key});

  @override
  State<PosOverviewScreen> createState() => _PosOverviewScreenState();
}

class _PosOverviewScreenState extends State<PosOverviewScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.today);
  bool _loading = true;
  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _stock;
  bool _topByRevenue = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final salesRes = await _api.getPosSalesReportSummary(
      from: _time.from,
      to: _time.to,
    );
    final stockRes = await _api.getPosStockReportSummary();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (salesRes['isSuccess'] == true && salesRes['data'] is Map) {
        _sales = Map<String, dynamic>.from(salesRes['data'] as Map);
      }
      if (stockRes['isSuccess'] == true && stockRes['data'] is Map) {
        _stock = Map<String, dynamic>.from(stockRes['data'] as Map);
      }
    });
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    return ColoredBox(
      color: PosTheme.background,
      child: RefreshIndicator(
        color: PosTheme.kiotBlue,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(12, inHub ? 8 : 12, 12, 24),
          children: [
            if (!inHub)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Tổng quan',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: PosTheme.textPrimary,
                  ),
                ),
              ),
            Container(
              decoration: PosTheme.mobileCardDecoration(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: PosKiotTimeFilter(
                state: _time,
                dense: true,
                onChanged: (s) async {
                  setState(() => _time = s);
                  await _load();
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: PosTheme.kiotBlue),
                ),
              )
            else ...[
              _buildSalesCard(),
              const SizedBox(height: 10),
              _buildStockCard(),
              const SizedBox(height: 10),
              _buildTopProductsCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSalesCard() {
    final s = _sales;
    final revenue = _num(s?['totalRevenue']);
    final orders = (s?['orderCount'] as num?)?.toInt() ?? 0;
    return _kiotCard(
      title: 'Doanh thu',
      subtitle: '$orders đơn · ${_time.displayLabel}',
      child: Text(
        _moneyFmt.format(revenue),
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: PosTheme.textPrimary,
        ),
      ),
      footer: s == null
          ? null
          : Row(
              children: [
                Expanded(
                  child: _miniStat(
                    'Đã thu',
                    _moneyFmt.format(_num(s['totalPaid'])),
                  ),
                ),
                Expanded(
                  child: _miniStat(
                    'Giảm giá',
                    _moneyFmt.format(_num(s['totalDiscount'])),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStockCard() {
    final st = _stock;
    return _kiotCard(
      title: 'Giá trị tồn',
      subtitle: '${(st?['productCount'] as num?)?.toInt() ?? 0} hàng hoá',
      child: Text(
        _moneyFmt.format(_num(st?['totalStockValue'] ?? st?['stockValue'])),
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: PosTheme.textPrimary,
        ),
      ),
      footer: st == null
          ? null
          : Row(
              children: [
                Expanded(
                  child: _miniStat(
                    'Tổng SL tồn',
                    _moneyFmt.format(_num(st['totalOnHandQty'] ?? st['onHandQty'])),
                  ),
                ),
                Expanded(
                  child: _miniStat(
                    'Hết hàng',
                    '${(st['outOfStockCount'] as num?)?.toInt() ?? 0}',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTopProductsCard() {
    final top = (_sales?['topProducts'] as List?) ?? [];
    if (top.isEmpty) {
      return _kiotCard(
        title: 'Hàng bán chạy',
        subtitle: 'Chưa có dữ liệu',
        child: const Text(
          '—',
          style: TextStyle(color: PosTheme.textSecondary),
        ),
      );
    }
    final sorted = [...top.whereType<Map>()];
    sorted.sort((a, b) {
      if (_topByRevenue) {
        return _num(b['revenue']).compareTo(_num(a['revenue']));
      }
      return _num(b['qty']).compareTo(_num(a['qty']));
    });

    return _kiotCard(
      title: 'Hàng bán chạy',
      subtitle: null,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chipToggle('Doanh thu', _topByRevenue, () {
            setState(() => _topByRevenue = true);
          }),
          const SizedBox(width: 6),
          _chipToggle('Số lượng', !_topByRevenue, () {
            setState(() => _topByRevenue = false);
          }),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < sorted.length && i < 10; i++) ...[
            if (i > 0) const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    sorted[i]['productName']?.toString() ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _moneyFmt.format(_num(sorted[i]['revenue'])),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${_num(sorted[i]['qty']).toStringAsFixed(_num(sorted[i]['qty']) == _num(sorted[i]['qty']).roundToDouble() ? 0 : 1)} sp',
                      style: const TextStyle(
                        fontSize: 11,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipToggle(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? PosTheme.kiotBlueLight : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kiotCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? footer,
    Widget? headerTrailing,
  }) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (headerTrailing != null) headerTrailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
