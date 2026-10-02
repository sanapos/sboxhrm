import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote_contract.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_contract_detail_screen.dart';

/// Công nợ hợp đồng: giá trị / đã thu / còn phải thu / quá hạn theo đợt thanh toán.
class PosContractReceivablesScreen extends StatefulWidget {
  const PosContractReceivablesScreen({super.key});

  @override
  State<PosContractReceivablesScreen> createState() => _PosContractReceivablesScreenState();
}

class _PosContractReceivablesScreenState extends State<PosContractReceivablesScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  static final _money = NumberFormat('#,##0', 'vi_VN');
  static final _date = DateFormat('dd/MM/yyyy');
  Timer? _debounce;
  String _filter = 'owing';
  bool _loading = true;
  String? _error;
  List<PosContractReceivable> _items = const [];
  Map<String, dynamic> _totals = const {};

  static const _filters = {
    'owing': 'Còn phải thu',
    'overdue': 'Quá hạn',
    'paid': 'Đã thu đủ',
    'all': 'Tất cả',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosContractReceivables(search: _search.text, filter: _filter);
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && data is Map) {
        _error = null;
        _items = ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PosContractReceivable.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals'] as Map) : const {};
      } else {
        _error = res['message']?.toString() ?? 'Không tải được công nợ hợp đồng';
      }
    });
  }

  double _t(String k) {
    final v = _totals[k];
    return v is num ? v.toDouble() : 0;
  }

  Widget _total(String label, double v, {Color? color}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(label), style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_money.format(v),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(title: Text(tr('Công nợ hợp đồng'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              decoration: InputDecoration(
                hintText: tr('Tìm số HĐ, báo giá, khách, SĐT'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tr(e.value)),
                      selected: _filter == e.key,
                      onSelected: (_) {
                        setState(() => _filter = e.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _total('Giá trị HĐ', _t('contractValue')),
                    _total('Đã thu', _t('collected'), color: Colors.green.shade700),
                    _total('Còn phải thu', _t('remaining'), color: PosTheme.kiotBlue),
                    _total('Quá hạn', _t('overdue'), color: Colors.red.shade700),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(tr(_error!)))
                    : _items.isEmpty
                        ? Center(child: Text(tr('Không có hợp đồng phù hợp')))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _row(_items[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _row(PosContractReceivable r) {
    final ratio = r.total > 0 ? (r.collected / r.total).clamp(0, 1).toDouble() : 0.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PosContractDetailScreen(quoteId: r.quoteId),
          ));
          if (mounted) await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [r.contractNo ?? r.quoteNo, r.customerName ?? ''].where((e) => e.isNotEmpty).join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_money.format(r.remaining),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: r.remaining > 0 ? PosTheme.kiotBlue : Colors.green.shade700,
                      )),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr('HĐ ${_money.format(r.total)} · đã thu ${_money.format(r.collected)}'
                    '${r.overdueAmount > 0 ? ' · quá hạn ${_money.format(r.overdueAmount)}' : ''}'),
                style: TextStyle(
                  fontSize: 12,
                  color: r.overdueAmount > 0 ? Colors.red.shade700 : SboxColors.slate600,
                ),
              ),
              if (r.nextDueTitle != null)
                Text(
                  tr('Đợt tới: ${r.nextDueTitle}${r.nextDueDate != null ? ' — hạn ${_date.format(r.nextDueDate!)}' : ''}'),
                  style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: SboxColors.slate200,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
