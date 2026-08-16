import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Công nợ NCC + nhập/trả theo kỳ.
class PosSupplierReportScreen extends StatefulWidget {
  const PosSupplierReportScreen({super.key});

  @override
  State<PosSupplierReportScreen> createState() => _PosSupplierReportScreenState();
}

class _PosSupplierReportScreenState extends State<PosSupplierReportScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  String _tab = 'debt';
  bool _loading = true;
  Map<String, dynamic>? _debt;
  Map<String, dynamic>? _purchases;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final debt = await _api.getPosSupplierDebtReport(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    final buy = await _api.getPosPurchasesReport(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _debt = debt['isSuccess'] == true && debt['data'] is Map
          ? Map<String, dynamic>.from(debt['data'] as Map)
          : null;
      _purchases = buy['isSuccess'] == true && buy['data'] is Map
          ? Map<String, dynamic>.from(buy['data'] as Map)
          : null;
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Widget _chip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: ${posReportMoney(amount)}',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PosReportMobileScaffold(
      title: 'Nhà cung cấp',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? ListView(children: const [
              SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: PosTheme.kiotBlue))),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(tr('Công nợ')),
                      selected: _tab == 'debt',
                      onSelected: (_) => setState(() => _tab = 'debt'),
                    ),
                    FilterChip(
                      label: Text(tr('Nhập / trả')),
                      selected: _tab == 'buy',
                      onSelected: (_) => setState(() => _tab = 'buy'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_tab == 'debt') ..._debtBody() else ..._buyBody(),
              ],
            ),
    );
  }

  List<Widget> _debtBody() {
    final items = ((_debt?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return [
      TextField(
        controller: _searchCtrl,
        decoration: PosTheme.inputDecoration(label: 'Tìm NCC'),
        onSubmitted: (_) => _load(),
      ),
      const SizedBox(height: 10),
      PosReportCard(
        title: '${_debt?['totalSuppliers'] ?? 0} NCC còn nợ',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosReportMoneyLabel(
              _n(_debt?['sumDebt']),
              fontSize: 18,
              maxWidth: 280,
              align: Alignment.centerLeft,
              color: const Color(0xFF2B3437),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('0–30', _n(_debt?['sumDebt0To30']), const Color(0xFF166534)),
                _chip('31–60', _n(_debt?['sumDebt31To60']), const Color(0xFFCA8A04)),
                _chip('61–90', _n(_debt?['sumDebt61To90']), Colors.orange.shade800),
                _chip('>90', _n(_debt?['sumDebtOver90']), Colors.red.shade700),
              ],
            ),
          ],
        ),
      ),
      PosReportCard(
        title: 'Chi tiết',
        child: items.isEmpty
            ? Text(tr('Không có nợ NCC'), style: const TextStyle(color: PosTheme.textSecondary))
            : Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _debtRow(items[i]),
                  ],
                ],
              ),
      ),
    ];
  }

  Widget _debtRow(Map<String, dynamic> r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(r['name']?.toString() ?? '—'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          '${r['phone'] ?? r['supplierCode'] ?? ''} · Nợ ${posReportMoney(_n(r['currentDebt']))} · phiếu mở ${posReportMoney(_n(r['openReceiptDebt']))}',
          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            if (_n(r['debt0To30']) > 0) _chip('0–30', _n(r['debt0To30']), const Color(0xFF166534)),
            if (_n(r['debt31To60']) > 0) _chip('31–60', _n(r['debt31To60']), const Color(0xFFCA8A04)),
            if (_n(r['debt61To90']) > 0) _chip('61–90', _n(r['debt61To90']), Colors.orange.shade800),
            if (_n(r['debtOver90']) > 0) _chip('>90', _n(r['debtOver90']), Colors.red.shade700),
          ],
        ),
      ],
    );
  }

  List<Widget> _buyBody() {
    final receipts = ((_purchases?['receipts'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final returns = ((_purchases?['returns'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return [
      PosReportCard(
        title: 'Nhập trong kỳ',
        child: PosReportMetricTiles(
          moneyFmt: _moneyFmt,
          tiles: [
            (label: 'Tiền nhập', value: _n(_purchases?['receiptAmount']), color: PosTheme.kiotBlue),
            (label: 'VAT', value: _n(_purchases?['receiptVat']), color: const Color(0xFF7C3AED)),
            (label: 'Đã trả NCC', value: _n(_purchases?['paidInPeriod']), color: const Color(0xFF166534)),
          ],
        ),
      ),
      PosReportCard(
        title: 'Trả NCC ${_purchases?['returnCount'] ?? 0} phiếu · ${posReportMoney(_n(_purchases?['returnAmount']))}',
        child: returns.isEmpty
            ? const PosReportEmpty(message: 'Không có phiếu trả')
            : Column(
                children: [
                  for (final r in returns)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('${r['returnNo']} · ${r['supplierName'] ?? ''}')),
                      subtitle: Text(tr(_fmtDate(r['date']))),
                      trailing: PosReportMoneyLabel(_n(r['totalAmount'])),
                    ),
                ],
              ),
      ),
      PosReportCard(
        title: 'Phiếu nhập (${_purchases?['receiptCount'] ?? receipts.length})',
        child: receipts.isEmpty
            ? const PosReportEmpty(message: 'Không có phiếu nhập')
            : Column(
                children: [
                  for (final r in receipts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('${r['receiptNo']} · ${r['supplierName'] ?? ''}')),
                      subtitle: Text(tr(
                          '${_fmtDate(r['date'])}${r['purchaseOrderNo'] != null ? ' · PO ${r['purchaseOrderNo']}' : ''}')),
                      trailing: PosReportMoneyLabel(_n(r['grandTotal'])),
                    ),
                ],
              ),
      ),
    ];
  }

  String _fmtDate(dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '' : _dateFmt.format(d);
  }
}
