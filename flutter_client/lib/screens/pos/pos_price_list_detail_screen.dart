import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_price_list.dart';
import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_price_list_resolver.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_unit_views.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_product_unit_view.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/pos_purchase_product_search_bar.dart';

/// Thiết lập giá chi tiết theo bảng giá — từng SP / biến thể / ĐVT.
class PosPriceListDetailScreen extends StatefulWidget {
  const PosPriceListDetailScreen({super.key, required this.priceList});

  final PosPriceList priceList;

  @override
  State<PosPriceListDetailScreen> createState() => _PosPriceListDetailScreenState();
}

class _PosPriceListDetailScreenState extends State<PosPriceListDetailScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _searchKey = GlobalKey<PosPurchaseProductSearchBarState>();

  Map<String, double> _overrides = {};
  bool _loadingOverrides = true;
  bool _saving = false;
  PosProduct? _selected;
  List<PosProductUnitView> _views = [];
  final Map<String, TextEditingController> _priceCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOverrides() async {
    setState(() => _loadingOverrides = true);
    final res = await _api.getPosPriceListResolvedPrices(widget.priceList.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _overrides = buildPosPriceOverrideMap(res['data'] as List);
        _loadingOverrides = false;
      });
    } else {
      setState(() => _loadingOverrides = false);
    }
  }

  void _clearPriceCtrls() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _priceCtrls.clear();
  }

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    _clearPriceCtrls();
    final p = pick.product;
    var views = await loadPosSellUnitViews(_api, p);
    if (!mounted) return;

    for (final v in views) {
      final key = posPriceListItemKey(
        productId: p.id,
        variantId: v.variantId,
        unitId: v.unitId,
      );
      final price = _overrides[key] ?? v.basePrice;
      _priceCtrls[key] = TextEditingController(
        text: price == price.roundToDouble()
            ? price.toStringAsFixed(0)
            : price.toStringAsFixed(2),
      );
    }

    setState(() {
      _selected = p;
      _views = views;
    });
  }

  Future<void> _saveProductPrices() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);

    final items = <Map<String, dynamic>>[];
    for (final v in _views) {
      final key = posPriceListItemKey(
        productId: _selected!.id,
        variantId: v.variantId,
        unitId: v.unitId,
      );
      final raw = _priceCtrls[key]?.text ?? '';
      final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
      final price = double.tryParse(cleaned) ?? 0;
      items.add({
        'productId': _selected!.id,
        if (v.variantId != null) 'variantId': v.variantId,
        if (v.unitId != null) 'unitId': v.unitId,
        'price': price,
      });
      _overrides[key] = price;
    }

    final res = await _api.upsertPosPriceListItems(widget.priceList.id, items);
    if (!mounted) return;
    setState(() => _saving = false);

    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: 'Giá ${_selected!.name} trong ${widget.priceList.name}',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được giá',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(widget.priceList.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loadingOverrides
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: PosPurchaseProductSearchBar(
                    key: _searchKey,
                    api: _api,
                    onPick: _onPickProduct,
                    hintText: 'Tìm hàng hoá để thiết lập giá…',
                  ),
                ),
                if (_selected != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      _selected!.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                      itemCount: _views.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final v = _views[i];
                        final key = posPriceListItemKey(
                          productId: _selected!.id,
                          variantId: v.variantId,
                          unitId: v.unitId,
                        );
                        final ctrl = _priceCtrls[key]!;
                        return Container(
                          decoration: PosTheme.mobileCardDecoration(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Giá gốc: ${_moneyFmt.format(v.basePrice)} đ',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: PosTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: ctrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[\d.]')),
                                  ],
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    suffixText: 'đ',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ] else
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Tìm và chọn hàng hoá để thiết lập giá theo bảng giá này.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PosTheme.textSecondary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _selected == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _saveProductPrices,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Đang lưu…' : 'Lưu giá'),
            ),
    );
  }
}
