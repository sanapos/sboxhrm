import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/navigation_notifier.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_kiot_time_filter.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/navigation_notifier.dart';

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
  Map<String, dynamic>? _analysis;
  bool _topByRevenue = true;

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posOverview.addListener(_onExternalRefresh);
    NavigationNotifier.currentModuleCode.addListener(_onModuleVisible);
    _load();
  }

  void _onExternalRefresh() {
    if (mounted) _load();
  }

  void _onModuleVisible() {
    if (!mounted) return;
    if (NavigationNotifier.currentModuleCode.value == 'PosSalesReport') {
      _load();
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posOverview.removeListener(_onExternalRefresh);
    NavigationNotifier.currentModuleCode.removeListener(_onModuleVisible);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getPosSalesReportSummary(from: _time.from, to: _time.to),
      _api.getPosStockReportSummary(),
      _api.getPosBusinessAnalysis(from: _time.from, to: _time.to),
    ]);
    if (!mounted) return;
    final salesRes = results[0];
    final stockRes = results[1];
    final analysisRes = results[2];
    setState(() {
      _loading = false;
      if (salesRes['isSuccess'] == true && salesRes['data'] is Map) {
        _sales = Map<String, dynamic>.from(salesRes['data'] as Map);
      }
      if (stockRes['isSuccess'] == true && stockRes['data'] is Map) {
        _stock = Map<String, dynamic>.from(stockRes['data'] as Map);
      }
      if (analysisRes['isSuccess'] == true && analysisRes['data'] is Map) {
        _analysis = Map<String, dynamic>.from(analysisRes['data'] as Map);
      } else {
        _analysis = null;
      }
    });
  }

  void _goHubTab(int index) {
    NavigationNotifier.posHubTab.value = index;
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inHub)
            PosMobileKiotHeader(
              title: 'Tổng quan',
              onRefresh: _load,
            ),
          Expanded(
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
                  ..._buildOverviewContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOverviewContent() {
    return [
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
              _buildQuickActions(),
              const SizedBox(height: 10),
              _buildSalesCard(),
              const SizedBox(height: 10),
              _buildProfitCard(),
              const SizedBox(height: 10),
              _buildStockAlertCard(),
              const SizedBox(height: 10),
              _buildStockCard(),
              const SizedBox(height: 10),
              _buildTopProductsCard(),
            ],
    ];
  }

  Widget _buildQuickActions() {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _quickAction(Icons.point_of_sale_outlined, 'Bán hàng', () => _goHubTab(2))),
          Expanded(child: _quickAction(Icons.inventory_2_outlined, 'Hàng hoá', () => _goHubTab(1))),
          Expanded(child: _quickAction(Icons.receipt_long_outlined, 'Hoá đơn', () => _goHubTab(3))),
          Expanded(child: _quickAction(Icons.more_horiz, 'Thêm', () => _goHubTab(4))),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: PosTheme.kiotBlue, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitCard() {
    final cur = _analysis?['current'] as Map?;
    if (cur == null) return const SizedBox.shrink();
    final profit = _num(cur['profit']);
    final margin = _num(cur['marginPct']);
    final avg = _num(cur['avgOrderValue']);
    final change = _analysis?['changePct'] as Map?;
    final profitChg = _num(change?['profit']);

    return _kiotCard(
      title: 'Lợi nhuận gộp',
      subtitle: 'Biên ${margin.toStringAsFixed(1)}% · TB đơn ${_moneyFmt.format(avg)}',
      child: Text(
        _moneyFmt.format(profit),
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: PosTheme.textPrimary,
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: _miniStat(
              'Giá vốn',
              _moneyFmt.format(_num(cur['cogs'])),
            ),
          ),
          Expanded(
            child: _miniStat(
              'So kỳ trước',
              '${profitChg >= 0 ? '+' : ''}${profitChg.toStringAsFixed(1)}%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockAlertCard() {
    final st = _stock;
    final out = (st?['outOfStockCount'] as num?)?.toInt() ??
        (st?['outOfStock'] as num?)?.toInt() ??
        0;
    final below = (st?['belowMin'] as num?)?.toInt() ?? 0;
    if (out == 0 && below == 0) return const SizedBox.shrink();

    return Container(
      decoration: PosTheme.mobileCardDecoration().copyWith(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00), size: 20),
              SizedBox(width: 8),
              Text(
                'Cảnh báo tồn kho',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (out > 0)
            Text('• $out hàng hoá đã hết hàng', style: const TextStyle(fontSize: 13)),
          if (below > 0)
            Text('• $below hàng hoá dưới mức tồn tối thiểu',
                style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _goHubTab(1),
              child: const Text('Xem hàng hoá'),
            ),
          ),
        ],
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
                    '${(st['outOfStockCount'] as num?)?.toInt() ?? (st['outOfStock'] as num?)?.toInt() ?? 0}',
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
