import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_kiot_time_filter.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import 'pos_business_analysis_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_sales_report_screen.dart';

/// Tổng quan POS mobile — layout đồng bộ với tab Nhiều hơn.
class PosOverviewScreen extends StatefulWidget {
  const PosOverviewScreen({super.key});

  @override
  State<PosOverviewScreen> createState() => _PosOverviewScreenState();
}

class _PosOverviewScreenState extends State<PosOverviewScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

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

  void _openHubScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: screen,
        ),
      ),
    );
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final user = auth.user;

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
                  PosMobileProfileCard(
                    name: user?.fullName ?? 'Cửa hàng',
                    subtitle: (user != null && user.email.isNotEmpty)
                        ? user.email
                        : (user?.position ??
                            user?.department ??
                            'Chi nhánh'),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickAccessSection(perm),
                  const SizedBox(height: 12),
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
                    _buildMetricsSection(),
                    ...() {
                      final alert = _buildStockAlertSection();
                      if (alert == null) return <Widget>[];
                      return [const SizedBox(height: 12), alert];
                    }(),
                    const SizedBox(height: 12),
                    _buildTopProductsSection(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessSection(PermissionProvider perm) {
    final items = <PosMobileHubGridItem>[
      PosMobileHubGridItem(
        label: 'Bán hàng',
        icon: Icons.shopping_bag_outlined,
        onTap: () => _goHubTab(2),
      ),
      PosMobileHubGridItem(
        label: 'Hàng hoá',
        icon: Icons.inventory_2_outlined,
        onTap: () => _goHubTab(1),
      ),
      PosMobileHubGridItem(
        label: 'Hoá đơn',
        icon: Icons.receipt_long_outlined,
        onTap: () => _goHubTab(3),
      ),
      if (PermissionNavigation.canNavigate(perm, 'PosSalesReport'))
        PosMobileHubGridItem(
          label: 'Báo cáo bán',
          icon: Icons.bar_chart_outlined,
          onTap: () => _openHubScreen(const PosSalesReportScreen()),
        ),
      if (PermissionNavigation.canNavigate(perm, 'PosSalesReport'))
        PosMobileHubGridItem(
          label: 'Cuối ngày',
          icon: Icons.nightlight_round,
          onTap: () => _openHubScreen(const PosEndOfDayScreen()),
        ),
      if (PermissionNavigation.canNavigate(perm, 'PosSalesReport'))
        PosMobileHubGridItem(
          label: 'Phân tích KD',
          icon: Icons.insights_outlined,
          onTap: () => _openHubScreen(const PosBusinessAnalysisScreen()),
        ),
      PosMobileHubGridItem(
        label: 'Nhiều hơn',
        icon: Icons.apps_outlined,
        onTap: () => _goHubTab(4),
      ),
    ];
    return PosMobileHubSectionGrid(
      title: 'Truy cập nhanh',
      items: items,
    );
  }

  Widget _buildMetricsSection() {
    final s = _sales;
    final st = _stock;
    final cur = _analysis?['current'] as Map?;
    final revenue = _num(s?['totalRevenue']);
    final orders = (s?['orderCount'] as num?)?.toInt() ?? 0;
    final profit = cur != null ? _num(cur['profit']) : 0.0;
    final margin = cur != null ? _num(cur['marginPct']) : 0.0;
    final stockValue = _num(st?['totalStockValue'] ?? st?['stockValue']);
    final productCount = (st?['productCount'] as num?)?.toInt() ?? 0;

    return PosMobileHubSection(
      title: 'Kết quả kinh doanh',
      trailing: Text(
        _time.displayLabel,
        style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.55,
        children: [
          PosMobileMetricTile(
            label: 'Doanh thu',
            icon: Icons.payments_outlined,
            value: '${_moneyFmt.format(revenue)} đ',
            subtitle: '$orders đơn · Đã thu ${_moneyFmt.format(_num(s?['totalPaid']))}',
          ),
          PosMobileMetricTile(
            label: 'Lợi nhuận gộp',
            icon: Icons.trending_up,
            value: cur != null ? '${_moneyFmt.format(profit)} đ' : '—',
            subtitle: cur != null
                ? 'Biên ${margin.toStringAsFixed(1)}%'
                : 'Chưa có dữ liệu',
            valueColor: cur != null && profit >= 0
                ? const Color(0xFF059669)
                : PosTheme.textPrimary,
          ),
          PosMobileMetricTile(
            label: 'Giá trị tồn',
            icon: Icons.inventory_outlined,
            value: '${_moneyFmt.format(stockValue)} đ',
            subtitle: '$productCount hàng hoá',
          ),
          PosMobileMetricTile(
            label: 'Giảm giá',
            icon: Icons.discount_outlined,
            value: '${_moneyFmt.format(_num(s?['totalDiscount']))} đ',
            subtitle: s != null ? 'Trong ${_time.displayLabel.toLowerCase()}' : null,
          ),
        ],
      ),
    );
  }

  Widget? _buildStockAlertSection() {
    final st = _stock;
    final out = (st?['outOfStockCount'] as num?)?.toInt() ??
        (st?['outOfStock'] as num?)?.toInt() ??
        0;
    final below = (st?['belowMin'] as num?)?.toInt() ?? 0;
    if (out == 0 && below == 0) return null;

    return Container(
      decoration: PosTheme.mobileCardDecoration().copyWith(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00), size: 20),
              SizedBox(width: 8),
              Text(
                'Cảnh báo tồn kho',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (out > 0)
            Text('• $out hàng hoá đã hết hàng',
                style: const TextStyle(fontSize: 13)),
          if (below > 0)
            Text('• $below hàng hoá dưới mức tồn tối thiểu',
                style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
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

  Widget _buildTopProductsSection() {
    final top = (_sales?['topProducts'] as List?) ?? [];
    if (top.isEmpty) {
      return PosMobileHubSection(
        title: 'Hàng bán chạy',
        child: const Text(
          'Chưa có dữ liệu trong kỳ đã chọn',
          style: TextStyle(color: PosTheme.textSecondary, fontSize: 13),
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

    return PosMobileHubSection(
      title: 'Hàng bán chạy',
      trailing: Row(
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
                Container(
                  width: 22,
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: PosTheme.kiotBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sorted[i]['productName']?.toString() ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_moneyFmt.format(_num(sorted[i]['revenue']))} đ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
