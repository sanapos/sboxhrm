import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_ui.dart';
class PosCustomerDebtReportScreen extends StatefulWidget {
  const PosCustomerDebtReportScreen({super.key});

  @override
  State<PosCustomerDebtReportScreen> createState() =>
      _PosCustomerDebtReportScreenState();
}

class _PosCustomerDebtReportScreenState extends State<PosCustomerDebtReportScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  double _sumDebt = 0;
  double _sum0 = 0;
  double _sum31 = 0;
  double _sum61 = 0;
  double _sum90 = 0;
  int _totalCustomers = 0;
  bool _includeZero = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomerDebtReport(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      includeZeroDebt: _includeZero,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        _sumDebt = (data['sumDebt'] is num)
            ? (data['sumDebt'] as num).toDouble()
            : double.tryParse('${data['sumDebt']}') ?? 0;
        _sum0 = _n(data['sumDebt0To30']);
        _sum31 = _n(data['sumDebt31To60']);
        _sum61 = _n(data['sumDebt61To90']);
        _sum90 = _n(data['sumDebtOver90']);
        _totalCustomers = (data['totalCustomers'] is num)
            ? (data['totalCustomers'] as num).toInt()
            : int.tryParse('${data['totalCustomers']}') ?? 0;
        _items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải báo cáo',
      );
    }
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    Widget money(double v, {bool strong = false, Color? color}) => Text(
          v > 0 ? SboxFmt.money(v) : '—',
          textAlign: TextAlign.right,
          style: (v <= 0
                  ? SboxType.bodyStyle(SboxColors.textMuted)
                  : (color != null ? SboxType.bodyStyle(color) : SboxType.bodyStyle()))
              .copyWith(fontWeight: strong ? SboxType.semibold : null),
        );
    return Scaffold(
      backgroundColor: SboxColors.page,
      body: SboxReportLayout(
        onRefresh: _load,
        filters: SboxFilterBar(
          searchHint: 'Tìm khách hàng',
          searchController: _searchCtrl,
          onSearch: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
          filters: [
            SboxFilterChip<bool>(
              label: 'Hiển thị',
              value: _includeZero,
              options: const {false: 'Khách còn nợ', true: 'Gồm khách nợ 0'},
              onChanged: (v) {
                setState(() => _includeZero = v);
                _load();
              },
            ),
          ],
        ),
        kpis: [
          SboxKpi(label: 'Tổng nợ phải thu', value: SboxFmt.money(_sumDebt), icon: Icons.account_balance_wallet_outlined, tone: SboxTone.danger),
          SboxKpi(label: 'Khách còn nợ', value: SboxFmt.number(_totalCustomers), icon: Icons.people_outline, tone: SboxTone.violet),
          SboxKpi(label: 'Nợ 0–30 ngày', value: SboxFmt.money(_sum0), icon: Icons.schedule_outlined, tone: SboxTone.success),
          SboxKpi(label: 'Quá 90 ngày', value: SboxFmt.money(_sum90), icon: Icons.warning_amber_rounded, tone: SboxTone.warning, note: 'Cần thu hồi gấp'),
        ],
        charts: [
          SboxChartCard(
            title: 'Tuổi nợ khách hàng',
            child: SboxBarChart(
              labels: const ['0–30 ngày', '31–60 ngày', '61–90 ngày', '> 90 ngày'],
              series: [
                SboxSeries(name: 'Khách nợ', color: SboxColors.danger, values: [_sum0, _sum31, _sum61, _sum90]),
              ],
            ),
          ),
          SboxChartCard(
            title: 'Khách nợ nhiều nhất',
            child: SboxRankList(
              color: SboxColors.danger,
              items: [for (final r in _items) SboxSlice(r['name']?.toString() ?? '—', _n(r['currentDebt']))],
            ),
          ),
        ],
        table: SboxCard(
          padding: EdgeInsets.zero,
          child: SboxDataTable<Map<String, dynamic>>(
            loading: _loading,
            rows: _items,
            pageSize: 50,
            emptyTitle: 'Không có khách còn nợ',
            columns: [
              SboxColumn(
                label: 'Khách hàng',
                primary: true,
                flex: 3,
                minWidth: 200,
                cell: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${r['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                  if (r['phone'] != null) Text('${r['phone']}', style: SboxType.smallStyle(SboxColors.textMuted)),
                ]),
              ),
              SboxColumn(label: 'Nợ hiện tại', numeric: true, minWidth: 130,
                  cell: (r) => money(_n(r['currentDebt']), strong: true, color: SboxColors.dangerText), sortValue: (r) => _n(r['currentDebt'])),
              SboxColumn(label: '0–30 ngày', numeric: true, minWidth: 110, hideOnMobile: true, cell: (r) => money(_n(r['debt0To30']))),
              SboxColumn(label: '31–60', numeric: true, minWidth: 110, hideOnMobile: true, cell: (r) => money(_n(r['debt31To60']))),
              SboxColumn(label: '61–90', numeric: true, minWidth: 110, hideOnMobile: true, cell: (r) => money(_n(r['debt61To90']))),
              SboxColumn(label: '> 90 ngày', numeric: true, minWidth: 110,
                  cell: (r) => money(_n(r['debtOver90']), color: SboxColors.dangerText), sortValue: (r) => _n(r['debtOver90'])),
            ],
          ),
        ),
      ),
    );
  }
}
