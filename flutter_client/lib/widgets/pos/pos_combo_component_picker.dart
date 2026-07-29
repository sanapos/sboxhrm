import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/paged_load_utils.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chọn hàng thành phần combo — tìm kiếm + phân trang API.
class PosComboComponentPicker extends StatefulWidget {
  const PosComboComponentPicker({
    super.key,
    required this.api,
    this.excludeProductId,
    this.excludeComponentIds = const {},
  });

  final ApiService api;
  final String? excludeProductId;
  final Set<String> excludeComponentIds;

  static Future<PosProduct?> show(
    BuildContext context, {
    required ApiService api,
    String? excludeProductId,
    Set<String> excludeComponentIds = const {},
  }) {
    return showDialog<PosProduct>(
      context: context,
      builder: (_) => PosComboComponentPicker(
        api: api,
        excludeProductId: excludeProductId,
        excludeComponentIds: excludeComponentIds,
      ),
    );
  }

  @override
  State<PosComboComponentPicker> createState() => _PosComboComponentPickerState();
}

class _PosComboComponentPickerState extends State<PosComboComponentPicker> {
  final _searchCtrl = TextEditingController();
  List<PosProduct> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String search) async {
    setState(() => _loading = true);
    final trimmed = search.trim();
    final maps = await fetchAllPagedMaps(
      (page, pageSize) => widget.api.getPosProducts(
        page: page,
        pageSize: pageSize,
        productType: PosProductType.goods,
        search: trimmed.isEmpty ? null : trimmed,
      ),
      pageSize: 500,
      maxPages: 20,
    );
    if (!mounted) return;
    final items = maps
        .map(PosProduct.fromJson)
        .where((p) =>
            p.id != widget.excludeProductId &&
            !widget.excludeComponentIds.contains(p.id))
        .toList();
    setState(() {
      _items = items;
      _loading = false;
      _query = trimmed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width < 520 ? width * 0.94 : 480.0;

    return AlertDialog(
      title: Text(tr('Chọn hàng thành phần')),
      content: SizedBox(
        width: dialogWidth,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: tr('Tìm mã, tên, mã vạch…'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: _load,
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : () => _load(_searchCtrl.text),
                icon: const Icon(Icons.search, size: 18),
                label: Text(tr('Tìm')),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            tr(_query.isEmpty
                                ? 'Không có hàng hóa'
                                : 'Không tìm thấy "$_query"'),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _items[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                tr(p.name),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(tr('${p.productCode} · Tồn: ${p.onHandQty}'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Đóng')),
        ),
      ],
    );
  }
}

/// Dialog nhập số lượng sau khi chọn thành phần.
Future<double?> showComboComponentQtyDialog(BuildContext context) async {
  final qtyCtrl = TextEditingController(text: tr('1'));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Số lượng thành phần')),
      content: TextField(
        controller: qtyCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: PosTheme.inputDecoration(label: 'Số lượng / 1 combo'),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(
          style: PosTheme.filledButtonStyle,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Thêm')),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
  if (qty <= 0) return null;
  return qty;
}
