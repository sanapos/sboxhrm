import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/image_compress.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

/// Super Admin — quản lý catalog hàng mẫu / menu món (ảnh dùng chung).
class PosSampleCatalogTab extends StatefulWidget {
  const PosSampleCatalogTab({super.key});

  @override
  State<PosSampleCatalogTab> createState() => PosSampleCatalogTabState();
}

class PosSampleCatalogTabState extends State<PosSampleCatalogTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  String? _kindFilter;
  String? _typeFilter;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    final res = await _api.getSystemPosSampleCatalog(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      kind: _kindFilter,
      includeInactive: true,
      pageSize: 200,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'];
      final list = data is Map ? data['items'] : null;
      var items = list is List
          ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (_typeFilter != null) {
        items = items
            .where((e) =>
                (e['productType'] ?? '').toString().toLowerCase() ==
                _typeFilter!.toLowerCase())
            .toList();
      }
      _items = items;
    } else {
      AdminHelpers.showApiError(context, res);
    }
    setState(() => _loading = false);
  }

  Future<void> _seed() async {
    final res = await _api.seedSystemPosSampleCatalog();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'];
      final created = data is Map ? data['created'] : null;
      final enriched = data is Map ? data['enriched'] : null;
      NotificationOverlayManager().showSuccess(
        title: 'Đã seed',
        message: tr(
          'Thêm mới: ${created ?? 0} · Bổ sung/cập nhật: ${enriched ?? 0}',
        ),
      );
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final isNew = row == null;
    final nameCtrl = TextEditingController(text: row?['name']?.toString() ?? '');
    final barcodeCtrl =
        TextEditingController(text: row?['barcode']?.toString() ?? '');
    final unitCtrl =
        TextEditingController(text: row?['unitName']?.toString() ?? 'Cái');
    final catCtrl =
        TextEditingController(text: row?['categoryName']?.toString() ?? '');
    final brandCtrl =
        TextEditingController(text: row?['brandName']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: row?['description']?.toString() ?? '');
    final priceCtrl = TextEditingController(
      text: row?['defaultPrice'] != null ? '${row!['defaultPrice']}' : '',
    );
    final costCtrl = TextEditingController(
      text: row?['defaultCostPrice'] != null
          ? '${row!['defaultCostPrice']}'
          : '',
    );
    var kind = row?['kind']?.toString() ?? 'Food';
    var productType = row?['productType']?.toString() ?? 'Goods';
    var vatRate = (row?['vatRate'] is num)
        ? (row!['vatRate'] as num).toDouble()
        : 8.0;
    var vatExempt = row?['vatExempt'] == true;
    if (vatExempt) vatRate = 0;
    var active = row?['isActive'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr(isNew ? 'Thêm hàng mẫu' : 'Sửa hàng mẫu')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: kind,
                    decoration: InputDecoration(labelText: tr('Nhóm mẫu')),
                    items: const [
                      DropdownMenuItem(
                          value: 'Packaged', child: Text('Có mã vạch')),
                      DropdownMenuItem(value: 'Food', child: Text('Món ăn')),
                      DropdownMenuItem(value: 'Drink', child: Text('Đồ uống')),
                    ],
                    onChanged: (v) => setLocal(() => kind = v ?? 'Food'),
                  ),
                  DropdownButtonFormField<String>(
                    value: productType,
                    decoration: InputDecoration(labelText: tr('Loại hàng *')),
                    items: const [
                      DropdownMenuItem(
                          value: 'Goods', child: Text('Hàng hóa')),
                      DropdownMenuItem(
                          value: 'Service', child: Text('Dịch vụ')),
                      DropdownMenuItem(value: 'Combo', child: Text('Combo')),
                      DropdownMenuItem(
                          value: 'Material', child: Text('Nguyên vật liệu')),
                      DropdownMenuItem(
                          value: 'Topping', child: Text('Topping')),
                    ],
                    onChanged: (v) =>
                        setLocal(() => productType = v ?? 'Goods'),
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: tr('Tên *')),
                  ),
                  TextField(
                    controller: barcodeCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Mã vạch (để trống nếu món F&B)'),
                    ),
                  ),
                  TextField(
                    controller: unitCtrl,
                    decoration: InputDecoration(labelText: tr('Đơn vị *')),
                  ),
                  TextField(
                    controller: catCtrl,
                    decoration:
                        InputDecoration(labelText: tr('Nhóm hàng gợi ý')),
                  ),
                  TextField(
                    controller: brandCtrl,
                    decoration: InputDecoration(labelText: tr('Thương hiệu')),
                  ),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Giá bán gợi ý')),
                  ),
                  TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Giá vốn gợi ý')),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Thuế GTGT'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(tr('KCT')),
                        selected: vatExempt,
                        onSelected: (_) => setLocal(() {
                          vatExempt = true;
                          vatRate = 0;
                        }),
                      ),
                      for (final r in [0.0, 5.0, 8.0, 10.0])
                        ChoiceChip(
                          label: Text('${r.toInt()}%'),
                          selected: !vatExempt && vatRate == r,
                          onSelected: (_) => setLocal(() {
                            vatExempt = false;
                            vatRate = r;
                          }),
                        ),
                    ],
                  ),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: tr('Mô tả')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Đang dùng')),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Lưu')),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu tên', message: tr('Nhập tên mẫu'));
      return;
    }
    if (unitCtrl.text.trim().isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thiếu ĐVT', message: tr('Nhập đơn vị tính'));
      return;
    }
    final body = {
      'name': name,
      'barcode':
          barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      'unitName': unitCtrl.text.trim(),
      'categoryName': catCtrl.text.trim(),
      'brandName': brandCtrl.text.trim(),
      'description':
          descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'kind': kind,
      'productType': productType,
      'defaultPrice': double.tryParse(priceCtrl.text.replaceAll(',', '')),
      'defaultCostPrice': double.tryParse(costCtrl.text.replaceAll(',', '')),
      'vatRate': vatExempt ? 0 : vatRate,
      'vatExempt': vatExempt,
      'isActive': active,
      'sortOrder': row?['sortOrder'] ?? 0,
    };
    final res = isNew
        ? await _api.createSystemPosSampleCatalog(body)
        : await _api.updateSystemPosSampleCatalog(row!['id'].toString(), body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await loadData();
      if (isNew && res['data'] is Map) {
        final id = res['data']['id']?.toString();
        if (id != null) await _uploadImage(id);
      }
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _uploadImage(String id) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final raw = f.bytes;
    if (raw == null || raw.isEmpty) return;
    final bytes = compressImageBytes(
      Uint8List.fromList(raw),
      maxEdge: 1200,
      jpegQuality: 75,
    );
    final name = bytes.length < raw.length
        ? jpegFileName(f.name.isEmpty ? 'sample.jpg' : f.name)
        : (f.name.isEmpty ? 'sample.jpg' : f.name);
    final res = await _api.uploadSystemPosSampleCatalogImage(
      id,
      bytes,
      name,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Ảnh',
        message: tr('Đã upload ảnh mẫu (dùng chung mọi cửa hàng)'),
      );
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mẫu?')),
        content: Text(tr('Ẩn «${row['name']}» khỏi catalog mẫu.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteSystemPosSampleCatalog(row['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  String _typeLabel(String? raw) {
    return posProductTypeLabel(posProductTypeFromString(raw));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: tr('Tìm tên / mã…'),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                  ),
                  onSubmitted: (_) => loadData(),
                ),
              ),
              DropdownButton<String?>(
                value: _kindFilter,
                hint: Text(tr('Tất cả nhóm')),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tất cả')),
                  DropdownMenuItem(value: 'Packaged', child: Text('Có mã vạch')),
                  DropdownMenuItem(value: 'Food', child: Text('Món ăn')),
                  DropdownMenuItem(value: 'Drink', child: Text('Đồ uống')),
                ],
                onChanged: (v) {
                  setState(() => _kindFilter = v);
                  loadData();
                },
              ),
              DropdownButton<String?>(
                value: _typeFilter,
                hint: Text(tr('Loại hàng')),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Mọi loại')),
                  DropdownMenuItem(value: 'Goods', child: Text('Hàng hóa')),
                  DropdownMenuItem(value: 'Service', child: Text('Dịch vụ')),
                  DropdownMenuItem(value: 'Combo', child: Text('Combo')),
                  DropdownMenuItem(
                      value: 'Material', child: Text('Nguyên vật liệu')),
                  DropdownMenuItem(value: 'Topping', child: Text('Topping')),
                ],
                onChanged: (v) {
                  setState(() => _typeFilter = v);
                  loadData();
                },
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Thêm mẫu')),
              ),
              OutlinedButton(
                onPressed: _seed,
                child: Text(tr('Seed / bổ sung mẫu')),
              ),
              IconButton(
                onPressed: loadData,
                icon: const Icon(Icons.refresh),
                tooltip: tr('Làm mới'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              tr('Ảnh upload 1 lần — cửa hàng adopt gắn path dùng chung. Seed cũng bổ sung mẫu DV/TP/NVL/CB + giá vốn/thuế.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? AdminHelpers.emptyState(
                      Icons.restaurant_menu, 'Chưa có hàng mẫu')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _row(_items[i]),
                    ),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final kind = row['kind']?.toString() ?? '';
    final active = row['isActive'] != false;
    final vat = row['vatExempt'] == true
        ? 'KCT'
        : (row['vatRate'] != null ? '${row['vatRate']}%' : null);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: ColoredBox(
            color: const Color(0xFFF0F2F5),
            child: id.isEmpty
                ? const Icon(Icons.image_outlined)
                : Image.network(
                    '${ApiService.baseUrl}/api/system-admin/pos-sample-catalog/$id/image',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      kind == 'Drink'
                          ? Icons.local_cafe_outlined
                          : kind == 'Food'
                              ? Icons.restaurant_outlined
                              : Icons.inventory_2_outlined,
                    ),
                  ),
          ),
        ),
      ),
      title: Text(tr('${row['name']}')),
      subtitle: Text(
        tr([
          _typeLabel(row['productType']?.toString()),
          kind,
          if ((row['barcode'] ?? '').toString().isNotEmpty) row['barcode'],
          row['unitName'],
          row['brandName'],
          row['categoryName'],
          if (row['defaultPrice'] != null) 'Giá ${row['defaultPrice']}',
          if (row['defaultCostPrice'] != null) 'Vốn ${row['defaultCostPrice']}',
          if (vat != null) vat,
          if (!active) 'Ẩn',
        ].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: tr('Ảnh'),
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => _uploadImage(id),
          ),
          IconButton(
            tooltip: tr('Sửa'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(row),
          ),
          IconButton(
            tooltip: tr('Xóa'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(row),
          ),
        ],
      ),
    );
  }
}
