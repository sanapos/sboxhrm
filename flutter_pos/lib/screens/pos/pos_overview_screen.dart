import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import 'package:sbox_pos/l10n/app_tr.dart';

/// Tổng quan POS — một bố cục gắn kết (số liệu + tồn + bán chạy), không trùng bottom nav.
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

  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final bottomPad = inHub ? PosTheme.mobileBottomNavHeight + 28.0 : 24.0;

    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inHub)
            PosMobileKiotHeader(
              title: 'Tổng quan',
              onRefresh: _load,
              trailing: [
                _PeriodChip(
                  label: _time.displayLabel,
                  onTap: () => _pickPeriod(context),
                ),
              ],
            ),
          Expanded(
            child: RefreshIndicator(
              color: PosTheme.kiotBlue,
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  return ListView(
                    padding:
                        EdgeInsets.fromLTRB(16, inHub ? 4 : 12, 16, bottomPad),
                    children: [
                      if (!inHub) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr('Tổng quan'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: PosTheme.textPrimary,
                                ),
                              ),
                            ),
                            _PeriodChip(
                              label: _time.displayLabel,
                              onTap: () => _pickPeriod(context),
                            ),
                            IconButton(
                              tooltip: tr('Làm mới'),
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      PosMobileProfileCard(
                        name: user?.fullName ?? 'Cửa hàng',
                        subtitle: (user != null && user.email.isNotEmpty)
                            ? user.email
                            : (user?.position ??
                                user?.department ??
                                'Chi nhánh'),
                      ),
                      const SizedBox(height: 14),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: PosTheme.kiotBlue,
                            ),
                          ),
                        )
                      else if (wide)
                        _buildWideBody()
                      else
                        _buildNarrowBody(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPeriod(BuildContext context) async {
    final picked = await showDialog<_OverviewPeriodChoice>(
      context: context,
      builder: (ctx) => _OverviewPeriodDialog(
        selected: _time.isCustom ? null : _time.preset,
        isCustom: _time.isCustom,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.custom) {
      if (!mounted) return;
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: this.context,
        firstDate: DateTime(2020),
        lastDate: now.add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(
          start: _time.from ?? DateTime(now.year, now.month, 1),
          end: _time.to ?? now,
        ),
        helpText: 'Chọn khoảng thời gian',
      );
      if (range == null || !mounted) return;
      setState(() {
        _time = PosKiotTimeFilterState(
          isCustom: true,
          customFrom: range.start,
          customTo: range.end,
        );
      });
    } else if (picked.preset != null) {
      setState(() {
        _time = PosKiotTimeFilterState(preset: picked.preset!, isCustom: false);
      });
    }
    await _load();
  }

  Widget _buildNarrowBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMetricsSection(),
        const SizedBox(height: 14),
        _buildRevenueChartSection(),
        ..._stockAlertSliver(),
        const SizedBox(height: 14),
        _buildTopProductsSection(),
      ],
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMetricsSection(),
              const SizedBox(height: 14),
              _buildRevenueChartSection(),
              ..._stockAlertSliver(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 4,
          child: _buildTopProductsSection(),
        ),
      ],
    );
  }

  List<Widget> _stockAlertSliver() {
    final alert = _buildStockAlertSection();
    if (alert == null) return const [];
    return [const SizedBox(height: 14), alert];
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
        tr(_time.displayLabel),
        style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: cols >= 4 ? 1.35 : 1.55,
            children: [
              PosMobileMetricTile(
                label: 'Doanh thu',
                icon: Icons.payments_outlined,
                value: '${_moneyFmt.format(revenue)} đ',
                subtitle:
                    '$orders đơn · Đã thu ${_moneyFmt.format(_num(s?['totalPaid']))}',
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
                subtitle: s != null
                    ? 'Trong ${_time.displayLabel.toLowerCase()}'
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Widget _buildRevenueChartSection() {
    final byDay = (_sales?['byDay'] as List?) ?? [];
    final points = byDay.whereType<Map>().map((d) {
      final dt = _parseDate(d['date']) ?? DateTime.now();
      return (date: dt, value: _num(d['total']));
    }).toList();

    return PosMobileHubSection(
      title: 'Doanh thu',
      trailing: Text(
        tr(_time.displayLabel),
        style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
      ),
      child: PosReportBarChart(points: points, height: 168),
    );
  }

  Widget? _buildStockAlertSection() {
    final st = _stock;
    final out = (st?['outOfStockCount'] as num?)?.toInt() ??
        (st?['outOfStock'] as num?)?.toInt() ??
        0;
    final below = (st?['belowMin'] as num?)?.toInt() ?? 0;
    if (out == 0 && below == 0) return null;

    return PosMobileHubSection(
      title: 'Cảnh báo tồn kho',
      trailing: const Icon(Icons.warning_amber_rounded,
          color: Color(0xFFF57C00), size: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (out > 0)
            Text(
              tr('• $out hàng hoá đã hết hàng'),
              style: const TextStyle(fontSize: 13),
            ),
          if (below > 0)
            Text(
              tr('• $below hàng hoá dưới mức tồn tối thiểu'),
              style: const TextStyle(fontSize: 13),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _goHubTab(1),
              child: Text(tr('Xem hàng hoá')),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tr('Chưa có dữ liệu trong kỳ đã chọn'),
            style: const TextStyle(color: PosTheme.textSecondary, fontSize: 13),
          ),
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
                    tr('${i + 1}'),
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
                    tr(sorted[i]['productName']?.toString() ?? '—'),
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
                      tr('${_moneyFmt.format(_num(sorted[i]['revenue']))} đ'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      tr(
                        '${_num(sorted[i]['qty']).toStringAsFixed(_num(sorted[i]['qty']) == _num(sorted[i]['qty']).roundToDouble() ? 0 : 1)} sp',
                      ),
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
            tr(label),
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

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PosTheme.kiotBlueLight,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 14, color: PosTheme.kiotBlue),
              const SizedBox(width: 6),
              Text(
                tr(label),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PosTheme.kiotBlue,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 16, color: PosTheme.kiotBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewPeriodChoice {
  const _OverviewPeriodChoice.preset(this.preset) : custom = false;
  const _OverviewPeriodChoice.custom()
      : preset = null,
        custom = true;

  final PosKiotTimePreset? preset;
  final bool custom;
}

class _OverviewPeriodDialog extends StatelessWidget {
  const _OverviewPeriodDialog({
    required this.selected,
    required this.isCustom,
  });

  final PosKiotTimePreset? selected;
  final bool isCustom;

  static const _presets = <(PosKiotTimePreset, String)>[
    (PosKiotTimePreset.today, 'Hôm nay'),
    (PosKiotTimePreset.yesterday, 'Hôm qua'),
    (PosKiotTimePreset.thisWeek, 'Tuần này'),
    (PosKiotTimePreset.thisMonth, 'Tháng này'),
    (PosKiotTimePreset.lastMonth, 'Tháng trước'),
  ];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(tr('Chọn kỳ')),
      children: [
        for (final o in _presets)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, _OverviewPeriodChoice.preset(o.$1)),
            child: Row(
              children: [
                Icon(
                  !isCustom && selected == o.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: !isCustom && selected == o.$1
                      ? PosTheme.kiotBlue
                      : PosTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(tr(o.$2)),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(context, const _OverviewPeriodChoice.custom()),
          child: Row(
            children: [
              Icon(
                isCustom
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
                color: isCustom ? PosTheme.kiotBlue : PosTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(tr('Tùy chỉnh…')),
            ],
          ),
        ),
      ],
    );
  }
}
