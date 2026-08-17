import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../models/pos_product.dart';
import 'pos_quick_add_barcode_sheet.dart';
import 'pos_theme.dart';

/// Duyệt catalog mẫu (món / đồ uống / hàng đóng gói) → thêm nhanh về cửa hàng.
Future<PosProduct?> showPosSampleCatalogPicker(
  BuildContext context,
  ApiService api, {
  String? initialKind,
  List<PosCatalogItem>? categories,
}) {
  return showModalBottomSheet<PosProduct>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _SampleCatalogPicker(
      api: api,
      initialKind: initialKind,
      categories: categories ?? const [],
    ),
  );
}

class _SampleCatalogPicker extends StatefulWidget {
  const _SampleCatalogPicker({
    required this.api,
    this.initialKind,
    required this.categories,
  });
  final ApiService api;
  final String? initialKind;
  final List<PosCatalogItem> categories;

  @override
  State<_SampleCatalogPicker> createState() => _SampleCatalogPickerState();
}

class _SampleCatalogPickerState extends State<_SampleCatalogPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  static const _kinds = [
    (null, 'Tất cả'),
    ('Food', 'Món ăn'),
    ('Drink', 'Đồ uống'),
    ('Packaged', 'Có mã vạch'),
  ];

  @override
  void initState() {
    super.initState();
    var idx = 0;
    if (widget.initialKind != null) {
      idx = _kinds.indexWhere((k) => k.$1 == widget.initialKind);
      if (idx < 0) idx = 0;
    }
    _tabs = TabController(length: _kinds.length, vsync: this, initialIndex: idx);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final kind = _kinds[_tabs.index].$1;
    final res = await widget.api.getPosSampleCatalog(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      kind: kind,
      pageSize: 100,
    );
    if (!mounted) return;
    final data = res['data'];
    final list = data is Map ? data['items'] : null;
    _items = list is List
        ? list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : [];
    setState(() => _loading = false);
  }

  Future<void> _pick(Map<String, dynamic> sample) async {
    final hint = PosBarcodeHint.fromSample(sample);
    final created = await showPosQuickAddByBarcode(
      context,
      widget.api,
      hint,
      categories: widget.categories,
    );
    if (created != null && mounted) {
      Navigator.pop(context, created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.88;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: PosTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Thêm từ menu / catalog mẫu'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              tr('Chọn món mẫu — xác nhận loại hàng, ĐVT, thương hiệu, thuế. Ảnh dùng chung, không upload lại.'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: PosTheme.kiotBlue,
            tabs: [for (final k in _kinds) Tab(text: tr(k.$2))],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: tr('Tìm tên / mã vạch…'),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _load,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text(tr('Không có mẫu phù hợp')))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _tile(_items[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final id = s['id']?.toString() ?? '';
    final name = s['name']?.toString() ?? '';
    final unit = s['unitName']?.toString() ?? '';
    final price = s['defaultPrice'];
    final priceText = price is num ? _money.format(price) : '—';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pick(s),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PosTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                  child: ColoredBox(
                    color: const Color(0xFFF5F7FA),
                    child: id.isEmpty
                        ? const Icon(Icons.restaurant_menu_outlined)
                        : FutureBuilder<List<int>?>(
                            future:
                                widget.api.getPosSampleCatalogImageBytes(id),
                            builder: (_, snap) {
                              if (snap.hasData &&
                                  snap.data != null &&
                                  snap.data!.isNotEmpty) {
                                return Image.memory(
                                  Uint8List.fromList(snap.data!),
                                  fit: BoxFit.cover,
                                );
                              }
                              return Icon(
                                (s['kind']?.toString() == 'Drink')
                                    ? Icons.local_cafe_outlined
                                    : (s['kind']?.toString() == 'Food')
                                        ? Icons.restaurant_outlined
                                        : Icons.inventory_2_outlined,
                                color: Colors.grey,
                              );
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr([
                        if ((s['productType'] ?? '').toString().isNotEmpty)
                          posProductTypeLabel(posProductTypeFromString(
                              s['productType']?.toString())),
                        priceText,
                        if (unit.isNotEmpty) unit,
                        if ((s['brandName'] ?? '').toString().isNotEmpty)
                          s['brandName'],
                      ].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
                      style: const TextStyle(
                        fontSize: 11,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
