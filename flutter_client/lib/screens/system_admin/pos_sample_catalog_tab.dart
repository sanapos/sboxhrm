import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/excel_download_helper.dart';
import '../../utils/image_compress.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

/// Super Admin — catalog hàng mẫu / menu món (ảnh dùng chung, Excel, nhóm hàng).
class PosSampleCatalogTab extends StatefulWidget {
  const PosSampleCatalogTab({super.key});

  @override
  State<PosSampleCatalogTab> createState() => PosSampleCatalogTabState();
}

class PosSampleCatalogTabState extends State<PosSampleCatalogTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');

  String? _kindFilter;
  String? _typeFilter;
  String? _categoryFilter;
  String? _brandFilter;
  String? _profileFilter;
  bool? _hasImageFilter;
  bool? _activeFilter;
  bool _loading = true;
  int _total = 0;
  int _imageNonce = 0;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _categories = [];
  List<String> _brands = [];

  static const _kinds = [
    (null, 'Tất cả loại mẫu'),
    ('Packaged', 'Có mã vạch'),
    ('Food', 'Món ăn'),
    ('Drink', 'Đồ uống'),
  ];

  static const _types = [
    (null, 'Mọi loại hàng'),
    ('Goods', 'Hàng hóa'),
    ('Service', 'Dịch vụ'),
    ('Combo', 'Combo'),
    ('Material', 'Nguyên vật liệu'),
    ('Topping', 'Topping'),
  ];

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

  String _imageUrl(String id) =>
      '${ApiService.baseUrl}/api/system-admin/pos-sample-catalog/$id/image?v=$_imageNonce';

  Future<void> loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getSystemPosSampleCatalog(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        kind: _kindFilter,
        productType: _typeFilter,
        category: _categoryFilter,
        brand: _brandFilter,
        sellProfile: _profileFilter,
        hasImage: _hasImageFilter,
        isActive: _activeFilter,
        includeInactive: _activeFilter == null,
        pageSize: 500,
      ),
      _api.getSystemPosSampleCatalogFacets(),
    ]);
    if (!mounted) return;
    final res = results[0];
    final facets = results[1];
    if (res['isSuccess'] == true) {
      final data = res['data'];
      final list = data is Map ? data['items'] : null;
      _total = data is Map ? (data['total'] as num?)?.toInt() ?? 0 : 0;
      _items = list is List
          ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
    } else {
      AdminHelpers.showApiError(context, res);
    }
    if (facets['isSuccess'] == true && facets['data'] is Map) {
      final d = Map<String, dynamic>.from(facets['data'] as Map);
      final cats = d['categories'];
      _categories = cats is List
          ? cats
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
      final brands = d['brands'];
      _brands = brands is List
          ? brands
              .map((e) => e is Map ? '${e['name'] ?? ''}' : '$e')
              .where((e) => e.isNotEmpty)
              .toList()
          : [];
    }
    setState(() => _loading = false);
  }

  Future<void> _seed() async {
    final res = await _api.seedSystemPosSampleCatalog();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'];
      NotificationOverlayManager().showSuccess(
        title: 'Đã seed',
        message: tr(
          'Thêm mới: ${data is Map ? data['created'] : 0} · '
          'Bổ sung: ${data is Map ? data['enriched'] : 0} · '
          'Nhóm hàng: ${data is Map ? data['groups'] : 0}',
        ),
      );
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _exportExcel({bool template = false}) async {
    final helper = ExcelDownloadHelper();
    final name = template
        ? 'Mau_catalog_mau_POS.xlsx'
        : 'Catalog_mau_POS_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
    final res = await helper.runServerExport(
      filename: name,
      fetch: () => template
          ? _api.exportSystemPosSampleCatalogExcelTemplate()
          : _api.exportSystemPosSampleCatalogExcel(
              search: _searchCtrl.text.trim().isEmpty
                  ? null
                  : _searchCtrl.text.trim(),
              kind: _kindFilter,
              productType: _typeFilter,
              category: _categoryFilter,
              brand: _brandFilter,
              hasImage: _hasImageFilter,
              includeInactive: _activeFilter == null,
            ),
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Excel',
        message: tr(template ? 'Đã tải file mẫu nhập' : 'Đã xuất catalog mẫu'),
      );
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.bytes == null || f.bytes!.isEmpty) return;
    final res = await _api.importSystemPosSampleCatalogExcel(
      f.bytes!,
      f.name.isEmpty ? 'catalog.xlsx' : f.name,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final d = res['data'];
      NotificationOverlayManager().showSuccess(
        title: 'Nhập Excel',
        message: tr(
          'Thêm ${d is Map ? d['created'] : 0} · '
          'Cập nhật ${d is Map ? d['updated'] : 0}',
        ),
      );
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _manageGroups() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SampleGroupsDialog(api: _api),
    );
    if (mounted) await loadData();
  }

  Future<void> _previewImage(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty || row['hasImage'] != true) {
      await _uploadImage(id);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('${row['name']}'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Đổi ảnh'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _uploadImage(id);
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Image.network(
                    _imageUrl(id),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined, size: 64),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final isNew = row == null;
    final nameCtrl = TextEditingController(text: row?['name']?.toString() ?? '');
    final barcodeCtrl =
        TextEditingController(text: row?['barcode']?.toString() ?? '');
    final unitCtrl =
        TextEditingController(text: row?['unitName']?.toString() ?? 'Cái');
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
    var selectedProfiles = _parseProfiles(row?['sellProfiles']);
    var categoryName = row?['categoryName']?.toString() ?? '';
    var categoryId = row?['categoryId']?.toString();
    var vatRate = (row?['vatRate'] is num)
        ? (row!['vatRate'] as num).toDouble()
        : 8.0;
    var vatExempt = row?['vatExempt'] == true;
    if (vatExempt) vatRate = 0;
    var active = row?['isActive'] != false;
    Uint8List? pendingImage;
    String pendingImageName = 'sample.jpg';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final catNames = {
            for (final c in _categories)
              if ((c['name'] ?? '').toString().isNotEmpty) '${c['name']}',
          };
          if (categoryName.isNotEmpty) catNames.add(categoryName);
          final catItems = ['', ...catNames];
          return AlertDialog(
            title: Text(tr(isNew ? 'Thêm hàng mẫu' : 'Sửa hàng mẫu')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isNew || pendingImage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (picked == null || picked.files.isEmpty) return;
                            final f = picked.files.first;
                            if (f.bytes == null) return;
                            setLocal(() {
                              pendingImage = Uint8List.fromList(f.bytes!);
                              pendingImageName =
                                  f.name.isEmpty ? 'sample.jpg' : f.name;
                            });
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: ColoredBox(
                                color: const Color(0xFFF0F2F5),
                                child: pendingImage != null
                                    ? Image.memory(pendingImage!,
                                        fit: BoxFit.contain)
                                    : (!isNew && row?['hasImage'] == true)
                                        ? Image.network(
                                            _imageUrl('${row!['id']}'),
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                    Icons.image_outlined,
                                                    size: 48),
                                          )
                                        : Center(
                                            child: Text(
                                              tr('Bấm để chọn ảnh (tới 1920px)'),
                                              style: TextStyle(
                                                  color: Colors.grey.shade600),
                                            ),
                                          ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      value: kind,
                      decoration: InputDecoration(labelText: tr('Loại mẫu')),
                      items: const [
                        DropdownMenuItem(
                            value: 'Packaged', child: Text('Có mã vạch')),
                        DropdownMenuItem(value: 'Food', child: Text('Món ăn')),
                        DropdownMenuItem(
                            value: 'Drink', child: Text('Đồ uống')),
                      ],
                      onChanged: (v) => setLocal(() => kind = v ?? 'Food'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          tr(selectedProfiles.isEmpty
                              ? 'Ngành (trống = mọi ngành)'
                              : 'Ngành áp dụng'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in PosSellProfile.values)
                          FilterChip(
                            label: Text(p.label, style: const TextStyle(fontSize: 12)),
                            selected: selectedProfiles.contains(p.apiValue),
                            onSelected: (on) => setLocal(() {
                              if (on) {
                                selectedProfiles.add(p.apiValue);
                              } else {
                                selectedProfiles.remove(p.apiValue);
                              }
                            }),
                          ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: productType,
                      decoration: InputDecoration(labelText: tr('Loại hàng *')),
                      items: const [
                        DropdownMenuItem(
                            value: 'Goods', child: Text('Hàng hóa')),
                        DropdownMenuItem(
                            value: 'Service', child: Text('Dịch vụ')),
                        DropdownMenuItem(
                            value: 'Combo', child: Text('Combo')),
                        DropdownMenuItem(
                            value: 'Material',
                            child: Text('Nguyên vật liệu')),
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
                    DropdownButtonFormField<String>(
                      value: catItems.contains(categoryName)
                          ? categoryName
                          : '',
                      decoration: InputDecoration(
                        labelText: tr('Nhóm hàng'),
                        helperText: tr('Chọn nhóm có sẵn hoặc tạo mới bên dưới'),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: '', child: Text(tr('(Chưa chọn)'))),
                        for (final n in catNames)
                          DropdownMenuItem(value: n, child: Text(n)),
                      ],
                      onChanged: (v) => setLocal(() {
                        categoryName = v ?? '';
                        categoryId = null;
                        for (final c in _categories) {
                          if ('${c['name']}' == categoryName) {
                            categoryId = c['id']?.toString();
                          }
                        }
                      }),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final created = await _promptNewGroup(kind);
                          if (created == null) return;
                          setLocal(() {
                            _categories = [..._categories, created];
                            categoryName = '${created['name']}';
                            categoryId = created['id']?.toString();
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Tạo nhóm hàng mới')),
                      ),
                    ),
                    TextField(
                      controller: brandCtrl,
                      decoration:
                          InputDecoration(labelText: tr('Thương hiệu')),
                    ),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: tr('Giá bán gợi ý')),
                    ),
                    TextField(
                      controller: costCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: tr('Giá vốn gợi ý')),
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
                    if (isNew)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked =
                                await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (picked == null || picked.files.isEmpty) {
                              return;
                            }
                            final f = picked.files.first;
                            if (f.bytes == null) return;
                            setLocal(() {
                              pendingImage = Uint8List.fromList(f.bytes!);
                              pendingImageName =
                                  f.name.isEmpty ? 'sample.jpg' : f.name;
                            });
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(tr(pendingImage == null
                              ? 'Chọn ảnh (1920px)'
                              : 'Đã chọn ảnh — bấm để đổi')),
                        ),
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
          );
        },
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
      'categoryName': categoryName.trim().isEmpty ? null : categoryName.trim(),
      'categoryId': categoryId,
      'brandName': brandCtrl.text.trim(),
      'description':
          descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'kind': kind,
      'productType': productType,
      'sellProfiles':
          selectedProfiles.isEmpty ? null : selectedProfiles.join(','),
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
      var id = isNew
          ? (res['data'] is Map ? res['data']['id']?.toString() : null)
          : row!['id'].toString();
      if (pendingImage != null && id != null) {
        await _uploadImageBytes(id, pendingImage!, pendingImageName);
      } else if (isNew && id != null && pendingImage == null) {
        await _uploadImage(id);
      }
      await loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<Map<String, dynamic>?> _promptNewGroup(String kind) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nhóm hàng mới')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Tên nhóm hàng')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Tạo'))),
        ],
      ),
    );
    if (ok != true) return null;
    final name = ctrl.text.trim();
    if (name.isEmpty) return null;
    final res = await _api.createSystemPosSampleCategory({
      'name': name,
      'kind': kind,
      'isActive': true,
    });
    if (!mounted) return null;
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    AdminHelpers.showApiError(context, res);
    return null;
  }

  Future<void> _uploadImage(String id) async {
    if (id.isEmpty) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final raw = f.bytes;
    if (raw == null || raw.isEmpty) return;
    await _uploadImageBytes(
        id, Uint8List.fromList(raw), f.name.isEmpty ? 'sample.jpg' : f.name);
  }

  Future<void> _uploadImageBytes(
      String id, Uint8List raw, String filename) async {
    final bytes = compressImageBytes(
      raw,
      maxEdge: 1920,
      jpegQuality: 88,
    );
    final name = bytes.length < raw.length
        ? jpegFileName(filename)
        : filename;
    final res = await _api.uploadSystemPosSampleCatalogImage(id, bytes, name);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _imageNonce++;
      NotificationOverlayManager().showSuccess(
        title: 'Ảnh',
        message: tr('Đã lưu ảnh 1920px — dùng chung mọi cửa hàng'),
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

  String _kindLabel(String? raw) {
    switch (raw) {
      case 'Food':
        return 'Món ăn';
      case 'Drink':
        return 'Đồ uống';
      case 'Packaged':
        return 'Có mã vạch';
      default:
        return raw ?? '';
    }
  }

  Set<String> _parseProfiles(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.trim().isEmpty) return <String>{};
    return {
      for (final p in s.split(','))
        if (p.trim().isNotEmpty) PosSellProfile.parse(p.trim()).apiValue,
    };
  }

  String _profileLabel(dynamic raw) {
    final set = _parseProfiles(raw);
    if (set.isEmpty) return 'Mọi ngành';
    return PosSellProfile.values
        .where((p) => set.contains(p.apiValue))
        .map((p) => p.label)
        .join(', ');
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
                    hintText: tr('Tìm tên / mã / nhóm…'),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                  ),
                  onSubmitted: (_) => loadData(),
                ),
              ),
              DropdownButton<String?>(
                value: _kindFilter,
                hint: Text(tr('Loại mẫu')),
                items: [
                  for (final k in _kinds)
                    DropdownMenuItem(value: k.$1, child: Text(tr(k.$2))),
                ],
                onChanged: (v) {
                  setState(() => _kindFilter = v);
                  loadData();
                },
              ),
              DropdownButton<String?>(
                value: _typeFilter,
                hint: Text(tr('Loại hàng')),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(value: t.$1, child: Text(tr(t.$2))),
                ],
                onChanged: (v) {
                  setState(() => _typeFilter = v);
                  loadData();
                },
              ),
              DropdownButton<String?>(
                value: _categories.any((c) => '${c['name']}' == _categoryFilter)
                    ? _categoryFilter
                    : null,
                hint: Text(tr('Nhóm hàng')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Mọi nhóm'))),
                  for (final c in _categories)
                    DropdownMenuItem(
                      value: '${c['name']}',
                      child: Text('${c['name']}'),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _categoryFilter = v);
                  loadData();
                },
              ),
              DropdownButton<String?>(
                value: _brands.contains(_brandFilter) ? _brandFilter : null,
                hint: Text(tr('Thương hiệu')),
                items: [
                  DropdownMenuItem(
                      value: null, child: Text(tr('Mọi thương hiệu'))),
                  for (final b in _brands)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (v) {
                  setState(() => _brandFilter = v);
                  loadData();
                },
              ),
              DropdownButton<String?>(
                value: _profileFilter,
                hint: Text(tr('Ngành')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Mọi ngành'))),
                  for (final p in PosSellProfile.values)
                    DropdownMenuItem(value: p.apiValue, child: Text(tr(p.label))),
                ],
                onChanged: (v) {
                  setState(() => _profileFilter = v);
                  loadData();
                },
              ),
              DropdownButton<bool?>(
                value: _hasImageFilter,
                hint: Text(tr('Ảnh')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Mọi ảnh'))),
                  DropdownMenuItem(value: true, child: Text(tr('Có ảnh'))),
                  DropdownMenuItem(value: false, child: Text(tr('Chưa ảnh'))),
                ],
                onChanged: (v) {
                  setState(() => _hasImageFilter = v);
                  loadData();
                },
              ),
              DropdownButton<bool?>(
                value: _activeFilter,
                hint: Text(tr('Trạng thái')),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tất cả')),
                  DropdownMenuItem(value: true, child: Text('Đang dùng')),
                  DropdownMenuItem(value: false, child: Text('Đã ẩn')),
                ],
                onChanged: (v) {
                  setState(() => _activeFilter = v);
                  loadData();
                },
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Thêm mẫu')),
              ),
              OutlinedButton.icon(
                onPressed: _manageGroups,
                icon: const Icon(Icons.category_outlined, size: 18),
                label: Text(tr('Nhóm hàng')),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportExcel(),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(tr('Xuất Excel')),
              ),
              OutlinedButton.icon(
                onPressed: _importExcel,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(tr('Nhập Excel')),
              ),
              TextButton(
                onPressed: () => _exportExcel(template: true),
                child: Text(tr('File mẫu')),
              ),
              TextButton(
                onPressed: _seed,
                child: Text(tr('Seed / bổ sung')),
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
              tr(
                '$_total mẫu · Gắn ngành để thu ngân chỉ thấy hàng đúng hồ sơ. '
                'Ảnh tới 1920px, dùng chung khi cửa hàng adopt. '
                'Excel: xuất/nhập tên, mã, nhóm, giá, thuế, ngành. Ảnh upload riêng.',
              ),
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
                  : LayoutBuilder(
                      builder: (ctx, box) {
                        final wide = box.maxWidth >= 720;
                        if (!wide) {
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => _row(_items[i]),
                          );
                        }
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _card(_items[i]),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final kind = row['kind']?.toString() ?? '';
    final active = row['isActive'] != false;
    final hasImage = row['hasImage'] == true;
    final price = row['defaultPrice'];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(row),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      child: ColoredBox(
                        color: const Color(0xFFF5F7FA),
                        child: hasImage && id.isNotEmpty
                            ? InkWell(
                                onTap: () => _previewImage(row),
                                child: Image.network(
                                  _imageUrl(id),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _kindIcon(kind),
                                ),
                              )
                            : InkWell(
                                onTap: () => _uploadImage(id),
                                child: _kindIcon(kind),
                              ),
                      ),
                    ),
                    if (!active)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: Chip(
                          label: Text('Ẩn', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _iconBtn(Icons.photo_camera_outlined,
                              () => _uploadImage(id)),
                          _iconBtn(Icons.delete_outline, () => _delete(row)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('${row['name']}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        _typeLabel(row['productType']?.toString()),
                        _kindLabel(kind),
                        _profileLabel(row['sellProfiles']),
                        row['categoryName'],
                        if (price is num) _money.format(price),
                      ]
                          .where((e) => e != null && '$e'.trim().isNotEmpty)
                          .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
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

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }

  Widget _kindIcon(String kind) {
    return Icon(
      kind == 'Drink'
          ? Icons.local_cafe_outlined
          : kind == 'Food'
              ? Icons.restaurant_outlined
              : Icons.inventory_2_outlined,
      color: Colors.grey,
      size: 40,
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
          width: 72,
          height: 72,
          child: ColoredBox(
            color: const Color(0xFFF0F2F5),
            child: id.isEmpty
                ? _kindIcon(kind)
                : Image.network(
                    _imageUrl(id),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _kindIcon(kind),
                  ),
          ),
        ),
      ),
      onTap: () => _previewImage(row),
      title: Text(tr('${row['name']}')),
      subtitle: Text(
        tr([
          _typeLabel(row['productType']?.toString()),
          _kindLabel(kind),
          _profileLabel(row['sellProfiles']),
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

class _SampleGroupsDialog extends StatefulWidget {
  const _SampleGroupsDialog({required this.api});
  final ApiService api;

  @override
  State<_SampleGroupsDialog> createState() => _SampleGroupsDialogState();
}

class _SampleGroupsDialogState extends State<_SampleGroupsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.api.getSystemPosSampleCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'];
      _items = data is List
          ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
    } else {
      AdminHelpers.showApiError(context, res);
    }
    setState(() => _loading = false);
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final nameCtrl =
        TextEditingController(text: row?['name']?.toString() ?? '');
    var kind = row?['kind']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(row == null ? 'Thêm nhóm hàng' : 'Sửa nhóm hàng')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Tên nhóm *')),
              ),
              DropdownButtonFormField<String?>(
                value: kind,
                decoration: InputDecoration(labelText: tr('Loại mẫu (tuỳ chọn)')),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Mọi loại')),
                  DropdownMenuItem(value: 'Packaged', child: Text('Có mã vạch')),
                  DropdownMenuItem(value: 'Food', child: Text('Món ăn')),
                  DropdownMenuItem(value: 'Drink', child: Text('Đồ uống')),
                ],
                onChanged: (v) => kind = v,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final body = {
      'name': name,
      'kind': kind,
      'sortOrder': row?['sortOrder'] ?? _items.length,
      'isActive': row?['isActive'] != false,
    };
    final res = row == null
        ? await widget.api.createSystemPosSampleCategory(body)
        : await widget.api
            .updateSystemPosSampleCategory(row['id'].toString(), body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa nhóm?')),
        content: Text(
          tr('Mẫu trong «${row['name']}» sẽ giữ tên nhóm, không còn gắn nhóm.'),
        ),
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
    final res =
        await widget.api.deleteSystemPosSampleCategory(row['id'].toString());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Nhóm hàng catalog mẫu')),
      content: SizedBox(
        width: 480,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Thêm nhóm')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(child: Text(tr('Chưa có nhóm — bấm Thêm nhóm')))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final row = _items[i];
                              return ListTile(
                                dense: true,
                                title: Text('${row['name']}'),
                                subtitle: Text(
                                  [
                                    if (row['kind'] != null) row['kind'],
                                    '${row['sampleCount'] ?? 0} mẫu',
                                  ].join(' · '),
                                ),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _edit(row),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(row),
                                    ),
                                  ],
                                ),
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
