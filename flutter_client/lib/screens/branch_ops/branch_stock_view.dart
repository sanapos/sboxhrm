import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_report.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'branch_ops_ui.dart';
import 'stock_transfer_screen.dart';

/// Tồn kho của 1 chi nhánh: KPI, lọc, danh sách; bấm hàng → tồn ở mọi chi nhánh + chuyển nhanh.
class BranchStockView extends StatefulWidget {
  const BranchStockView({super.key, this.branchId, this.embedded = false});

  /// null = chi nhánh đang thao tác (và cho chọn chi nhánh khác).
  final String? branchId;
  final bool embedded;

  @override
  State<BranchStockView> createState() => _BranchStockViewState();
}

class _BranchStockViewState extends State<BranchStockView> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _branchId;
  String _filter = '';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchId ?? BranchSession.instance.writeBranchId;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getBranchStock(branchId: _branchId, search: _search.text, filter: _filter, pageSize: 300);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = r['message']?.toString() ?? 'Không tải được tồn kho';
      }
    });
  }

  List<Map<String, dynamic>> get _items =>
      [for (final x in (_data['items'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  Future<void> _showMatrix(Map<String, dynamic> item) async {
    final r = await _api.getBranchStockMatrix(item['productId'].toString());
    if (!mounted) return;
    final branches = [
      for (final b in ((r['data'] as Map?)?['branches'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)
    ];
    final maxQty = branches.fold<double>(0, (m, b) => bNum(b['qty']) > m ? bNum(b['qty']) : m);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item['name']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(tr('Tổng tồn cả cửa hàng: ${bQty(item['totalQty'])} ${item['unit'] ?? ''}'),
                style: const TextStyle(color: SboxColors.slate500, fontSize: 12.5)),
            const SizedBox(height: 12),
            for (final b in branches)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(tr('${b['name']}${b['isHeadquarter'] == true ? ' (trụ sở)' : ''}'),
                          style: TextStyle(
                              fontWeight: b['id'].toString() == _branchId ? FontWeight.w800 : FontWeight.w600)),
                    ),
                    Text(bQty(b['qty']),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: bNum(b['qty']) <= 0 ? SboxColors.danger : SboxColors.slate900)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: maxQty <= 0 ? 0 : (bNum(b['qty']) / maxQty).clamp(0, 1).toDouble(),
                      backgroundColor: SboxColors.slate100,
                      color: SboxColors.brand500,
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StockTransferScreen(
                    prefillProduct: item,
                    prefillToBranchId: _branchId,
                  ),
                ));
              },
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(tr('Chuyển hàng về chi nhánh này')),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = BranchSession.instance;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 0 : 14, 12, widget.embedded ? 0 : 14, 24),
        children: [
          if (widget.branchId == null && s.showSwitcher)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final b in s.branches)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.storefront_rounded, size: 16),
                        label: Text(tr(b.name)),
                        selected: _branchId == b.id,
                        onSelected: (_) {
                          setState(() => _branchId = b.id);
                          _load();
                        },
                      ),
                    ),
                ]),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _load);
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm tên, mã, mã vạch…'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in const [('', 'Tất cả'), ('instock', 'Còn hàng'), ('low', 'Sắp hết'), ('out', 'Hết hàng')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(f.$2)),
                    selected: _filter == f.$1,
                    onSelected: (_) {
                      setState(() => _filter = f.$1);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            BranchBox(child: Text(tr(_error!)))
          else ...[
            SboxKpiStrip(maxColumns: 4, items: [
              SboxKpi(
                label: 'Giá trị tồn',
                value: bMoneyShort(_data['totalValue']),
                icon: Icons.inventory_2_outlined,
                tone: SboxTone.brand,
                note: '${bQty(_data['totalCount'])} mặt hàng',
              ),
              SboxKpi(label: 'Tổng số lượng', value: bQty(_data['totalQty']), icon: Icons.numbers_rounded, tone: SboxTone.neutral),
              SboxKpi(
                label: 'Sắp hết',
                value: bQty(_data['lowStock']),
                icon: Icons.warning_amber_rounded,
                tone: bNum(_data['lowStock']) > 0 ? SboxTone.warning : SboxTone.success,
                onTap: () {
                  setState(() => _filter = 'low');
                  _load();
                },
              ),
              SboxKpi(
                label: 'Hết hàng',
                value: bQty(_data['outOfStock']),
                icon: Icons.remove_shopping_cart_outlined,
                tone: bNum(_data['outOfStock']) > 0 ? SboxTone.danger : SboxTone.success,
                onTap: () {
                  setState(() => _filter = 'out');
                  _load();
                },
              ),
            ]),
            const SizedBox(height: 10),
            if (_items.isEmpty)
              BranchBox(child: Center(child: Text(tr('Không có hàng phù hợp'))))
            else
              for (final it in _items) _row(it),
          ],
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      // Trong khung chính thanh trên đã có tiêu đề — không lặp.
      appBar: HrmPageChrome.hideInPageTitle(context) ? null : AppBar(title: Text(tr('Kho chi nhánh'))),
      body: body,
    );
  }

  Widget _row(Map<String, dynamic> it) {
    final qty = bNum(it['qty']);
    final min = bNum(it['minStockQty']);
    final color = qty <= 0 ? SboxColors.danger : (min > 0 && qty < min ? SboxColors.warning : SboxColors.success);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _showMatrix(it),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.inventory_2_rounded, size: 18, color: color),
        ),
        title: Text(it['name']?.toString() ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          tr('${it['productCode'] ?? ''} · cả cửa hàng ${bQty(it['totalQty'])}${min > 0 ? ' · tối thiểu ${bQty(min)}' : ''}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${bQty(qty)} ${it['unit'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          Text(bMoney(bNum(it['stockValue'])), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
        ]),
      ),
    );
  }
}
