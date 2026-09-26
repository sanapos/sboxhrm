import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/image_source_picker.dart';
import '../notification_overlay.dart';
import 'pos_product_image.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Chụp / chọn ảnh menu → AI (Gemini) đọc tên món, nhóm, giá, size, gợi ý ảnh catalog mẫu
/// → xem trước, sửa → tạo nhóm hàng / hàng hóa / size. Trả `true` nếu đã tạo hàng.
Future<bool> showPosAiMenuImport(BuildContext context, ApiService api) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PosAiMenuImportPage(api: api),
    ),
  );
  return created == true;
}

class _MenuRow {
  _MenuRow(Map<String, dynamic> j)
      : include = j['existingProductId'] == null,
        name = TextEditingController(text: (j['name'] ?? '').toString()),
        category = TextEditingController(text: (j['category'] ?? '').toString()),
        price = TextEditingController(text: _fmt((j['price'] as num?) ?? 0)),
        sizes = TextEditingController(text: _sizesText(j['sizes'])),
        unit = (j['unit'] ?? '').toString(),
        description = j['description']?.toString(),
        imageUrl = j['imageUrl']?.toString(),
        sampleCatalogId = j['sampleCatalogId']?.toString(),
        sampleCatalogName = j['sampleCatalogName']?.toString(),
        existingProductName = j['existingProductName']?.toString();

  bool include;
  final TextEditingController name;
  final TextEditingController category;
  final TextEditingController price;
  final TextEditingController sizes;
  final String unit;
  final String? description;
  String? imageUrl;
  final String? sampleCatalogId;
  final String? sampleCatalogName;
  final String? existingProductName;

  static final _money = NumberFormat.decimalPattern('vi');
  static String _fmt(num v) => v <= 0 ? '' : _money.format(v);

  static String _sizesText(dynamic raw) {
    if (raw is! List) return '';
    return raw
        .whereType<Map>()
        .map((s) => '${s['name']} ${_fmt((s['price'] as num?) ?? 0)}')
        .join('; ');
  }

  static double _money2num(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// "M 30.000; L 38.000" → [{name: M, price: 30000}, ...]
  List<Map<String, dynamic>> parsedSizes() {
    final out = <Map<String, dynamic>>[];
    for (final part in sizes.text.split(RegExp(r'[;\n]'))) {
      final m = RegExp(r'^\s*(.+?)\s+([0-9][0-9.,\s]*)\s*$').firstMatch(part);
      if (m == null) continue;
      out.add({'name': m.group(1)!.trim(), 'price': _money2num(m.group(2)!)});
    }
    return out;
  }

  Map<String, dynamic> toJson() {
    final sz = parsedSizes();
    return {
      'name': name.text.trim(),
      'category': category.text.trim().isEmpty ? null : category.text.trim(),
      'price': sz.isNotEmpty
          ? sz.map((s) => s['price'] as double).reduce((a, b) => a < b ? a : b)
          : _money2num(price.text),
      'sizes': sz,
      'unit': unit.isEmpty ? null : unit,
      'description': description,
      'imageUrl': imageUrl,
      'sampleCatalogId': sampleCatalogId,
      'sampleCatalogName': sampleCatalogName,
      'existingProductId': null,
      'existingProductName': existingProductName,
    };
  }

  void dispose() {
    name.dispose();
    category.dispose();
    price.dispose();
    sizes.dispose();
  }
}

class _PosAiMenuImportPage extends StatefulWidget {
  const _PosAiMenuImportPage({required this.api});
  final ApiService api;

  @override
  State<_PosAiMenuImportPage> createState() => _PosAiMenuImportPageState();
}

class _PosAiMenuImportPageState extends State<_PosAiMenuImportPage> {
  static const _maxImages = 8;
  final _images = <PickedImageResult>[];
  final _rows = <_MenuRow>[];
  bool _scanning = false;
  bool _importing = false;
  /// Lỗi đọc menu hiện ngay trên trang (thông báo nổi có thể bị che bởi trang toàn màn hình).
  String? _scanError;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _addImages() async {
    // Chữ trên menu cần độ phân giải cao hơn ảnh sản phẩm.
    final picked = await pickImagesWithCamera(context,
        allowMultiple: true, maxEdge: 2200, jpegQuality: 85);
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _images.addAll(picked.take(_maxImages - _images.length));
    });
  }

  Future<void> _scan() async {
    if (_images.isEmpty) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    final res = await widget.api.scanPosMenuAi([
      for (final i in _images) (bytes: i.bytes, name: i.name),
    ]);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (res['isSuccess'] != true) {
      final msg = res['message']?.toString() ?? tr('Vui lòng thử lại sau');
      setState(() => _scanError = msg);
      NotificationOverlayManager().showError(
        title: tr('Không đọc được menu'),
        message: msg,
      );
      return;
    }
    final items = (res['data']?['items'] as List?) ?? const [];
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll(items.whereType<Map>().map((e) => _MenuRow(Map<String, dynamic>.from(e))));
    });
  }

  Future<void> _import() async {
    final chosen = _rows.where((r) => r.include && r.name.text.trim().isNotEmpty).toList();
    if (chosen.isEmpty) return;
    setState(() => _importing = true);
    final res = await widget.api.importPosMenuAi(chosen.map((r) => r.toJson()).toList());
    if (!mounted) return;
    setState(() => _importing = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không tạo được hàng hóa'),
        message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
      );
      return;
    }
    final d = res['data'] as Map? ?? const {};
    final skipped = (d['skipped'] as List?)?.length ?? 0;
    NotificationOverlayManager().showSuccess(
      title: tr('Đã tạo ${d['productsCreated'] ?? 0} món'),
      message: tr('${d['categoriesCreated'] ?? 0} nhóm mới · ${d['variantsCreated'] ?? 0} size') +
          (skipped > 0 ? tr(' · bỏ qua $skipped món đã có') : ''),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _rows.where((r) => r.include).length;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Tạo hàng từ ảnh menu (AI)')),
        actions: [
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _importing || selected == 0 ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(tr('Tạo $selected món')),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildImagesCard(),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              tr('Kiểm tra lại trước khi tạo. Size ghi dạng «M 30.000; L 38.000». Món đã có trong cửa hàng được bỏ chọn sẵn.'),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final r in _rows) _buildRow(r),
          ],
        ],
      ),
    );
  }

  Widget _buildImagesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Ảnh menu (tối đa $_maxImages ảnh, chụp thẳng, rõ chữ)'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _images.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_images[i].bytes,
                            width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: _scanning ? null : () => setState(() => _images.removeAt(i)),
                          child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                if (_images.length < _maxImages)
                  InkWell(
                    onTap: _scanning ? null : _addImages,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border.all(color: PosTheme.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scanning || _images.isEmpty ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_scanning
                  ? tr('AI đang đọc menu… (có thể mất 30–60 giây)')
                  : (_rows.isEmpty ? tr('Đọc menu bằng AI') : tr('Đọc lại'))),
            ),
            if (_scanError != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF9A9A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${tr('Không đọc được menu')}: $_scanError',
                        style: const TextStyle(color: Color(0xFFB71C1C)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(_MenuRow r) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: tr(label),
          isDense: true,
          border: const OutlineInputBorder(),
        );
    return Card(
      color: r.include ? null : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: r.include,
              onChanged: (v) => setState(() => r.include = v ?? false),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 10),
              child: Column(
                children: [
                  r.imageUrl == null
                      ? Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported_outlined, size: 20),
                        )
                      : PosProductImage(imageUrl: r.imageUrl, size: 56),
                  if (r.imageUrl != null)
                    TextButton(
                      onPressed: () => setState(() => r.imageUrl = null),
                      child: Text(tr('Bỏ ảnh'), style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(width: 240, child: TextField(controller: r.name, decoration: deco('Tên món'))),
                      SizedBox(width: 170, child: TextField(controller: r.category, decoration: deco('Nhóm'))),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: r.price,
                          keyboardType: TextInputType.number,
                          decoration: deco('Giá'),
                        ),
                      ),
                      SizedBox(width: 240, child: TextField(controller: r.sizes, decoration: deco('Size (tùy chọn)'))),
                    ],
                  ),
                  if (r.sampleCatalogName != null || r.existingProductName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (r.sampleCatalogName != null) tr('Ảnh mẫu: ${r.sampleCatalogName}'),
                          if (r.existingProductName != null)
                            tr('Đã có hàng «${r.existingProductName}»'),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: r.existingProductName != null
                              ? Colors.orange.shade800
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
