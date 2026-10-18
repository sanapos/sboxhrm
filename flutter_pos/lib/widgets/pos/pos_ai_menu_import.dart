import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/image_source_picker.dart';
import '../notification_overlay.dart';
import 'pos_product_image.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
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

const _priceSuffix = r'(k|nghìn|ngàn|tr|triệu)';

/// Giá gõ trên màn xem trước: "35.000" → 35000, "35k" → 35000, "1,2tr" → 1200000.
double parseMenuPrice(String s) {
  final t = s.toLowerCase().replaceAll(RegExp(r'\s'), '');
  final m = RegExp('^([0-9]+(?:[.,][0-9]+)*)$_priceSuffix?').firstMatch(t);
  if (m == null) return 0;
  final suffix = m.group(2);
  if (suffix == null) {
    return double.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
  }
  final n = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
  return (n * (suffix == 'tr' || suffix == 'triệu' ? 1000000 : 1000)).roundToDouble();
}

/// "M 30.000; L 38k" → [{name: M, price: 30000}, {name: L, price: 38000}].
/// Size không ghi giá («XL») vẫn giữ với giá 0 để báo người dùng (server lấy giá món).
List<Map<String, dynamic>> parseMenuSizes(String text) {
  final out = <Map<String, dynamic>>[];
  final re = RegExp('^\\s*(.+?)\\s+([0-9][0-9.,\\s]*$_priceSuffix?)\\s*\$', caseSensitive: false);
  for (final part in text.split(RegExp(r'[;\n]'))) {
    if (part.trim().isEmpty) continue;
    final m = re.firstMatch(part);
    if (m == null) {
      out.add({'name': part.trim(), 'price': 0.0});
      continue;
    }
    out.add({'name': m.group(1)!.trim(), 'price': parseMenuPrice(m.group(2)!)});
  }
  return out;
}

/// "Cơm gà x2; Trà đá" → [{name: Cơm gà, qty: 2}, {name: Trà đá, qty: 1}]
List<Map<String, dynamic>> parseComboItems(String text) {
  final out = <Map<String, dynamic>>[];
  for (final part in text.split(RegExp(r'[;\n+]'))) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^(.+?)\s*[x×]\s*([0-9]+(?:[.,][0-9]+)?)$', caseSensitive: false).firstMatch(t);
    if (m == null) {
      out.add({'name': t, 'qty': 1.0});
    } else {
      out.add({'name': m.group(1)!.trim(), 'qty': double.tryParse(m.group(2)!.replaceAll(',', '.')) ?? 1});
    }
  }
  return out;
}

String comboItemsText(dynamic raw) {
  if (raw is! List) return '';
  return raw.whereType<Map>().map((c) {
    final q = (c['qty'] as num?) ?? 1;
    return q == 1 ? '${c['name']}' : '${c['name']} x${q % 1 == 0 ? q.toInt() : q}';
  }).join('; ');
}

/// "Trà sữa, Trà trái cây" → ['Trà sữa', 'Trà trái cây']
List<String> parseNameList(String text) => text
    .split(RegExp(r'[,;\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Loại hàng trên màn xem trước (giá trị = tên enum PosProductType phía server).
const menuProductTypes = <String, String>{
  'Goods': 'Hàng hóa',
  'Service': 'Dịch vụ',
  'Combo': 'Combo',
  'Topping': 'Topping',
  'Material': 'Nguyên liệu',
};

/// Cách tính tiền dịch vụ (tên enum PosServiceBillingMode).
const menuBillingModes = <String, String>{
  'Flat': 'Giá cố định',
  'PerHour': 'Theo giờ',
  'PerDay': 'Theo ngày / đêm',
  'PerSession': 'Gói buổi',
};

/// Loại hàng bán theo size (combo / topping / nguyên liệu bỏ size).
bool menuTypeHasSizes(String type) => type == 'Goods' || type == 'Service';

/// Cảnh báo một dòng trước khi tạo: chưa có giá, size thiếu giá.
List<String> menuRowWarnings({
  required String type,
  required double price,
  required List<Map<String, dynamic>> sizes,
}) {
  if (type == 'Material') return const [];
  final useSizes = menuTypeHasSizes(type) && sizes.isNotEmpty;
  final priced = useSizes ? sizes.where((s) => (s['price'] as num) > 0).toList() : const [];
  final out = <String>[];
  if (useSizes ? priced.isEmpty : price <= 0) out.add('Chưa có giá');
  if (useSizes && priced.isNotEmpty) {
    final missing = sizes.where((s) => (s['price'] as num) <= 0).map((s) => s['name']).toList();
    if (missing.isNotEmpty) {
      out.add('Size ${missing.join(', ')} chưa có giá — sẽ lấy giá size rẻ nhất');
    }
  }
  return out;
}

class _MenuRow {
  _MenuRow(Map<String, dynamic> j)
      : include = j['existingProductId'] == null,
        name = TextEditingController(text: (j['name'] ?? '').toString()),
        category = TextEditingController(text: (j['category'] ?? '').toString()),
        price = TextEditingController(text: _fmt((j['price'] as num?) ?? 0)),
        sizes = TextEditingController(text: _sizesText(j['sizes'])),
        unit = TextEditingController(text: (j['unit'] ?? '').toString()),
        type = menuProductTypes.containsKey(j['productType']) ? j['productType'] as String : 'Goods',
        billing = menuBillingModes.containsKey(j['billing']) ? j['billing'] as String : 'Flat',
        sessions = TextEditingController(
            text: ((j['sessionCount'] as num?) ?? 0) > 0 ? '${j['sessionCount']}' : ''),
        toppingFor = TextEditingController(
            text: ((j['toppingFor'] as List?) ?? const []).map((e) => '$e').join(', ')),
        comboItems = TextEditingController(text: comboItemsText(j['comboItems'])),
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
  final TextEditingController unit;
  String type;
  String billing;
  final TextEditingController sessions;
  final TextEditingController toppingFor;
  final TextEditingController comboItems;
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
        .map((s) => '${s['name']} ${_fmt((s['price'] as num?) ?? 0)}'.trim())
        .join('; ');
  }

  List<Map<String, dynamic>> parsedSizes() =>
      menuTypeHasSizes(type) ? parseMenuSizes(sizes.text) : const [];

  List<String> warnings() => menuRowWarnings(
        type: type,
        price: parseMenuPrice(price.text),
        sizes: parsedSizes(),
      );

  Map<String, dynamic> toJson() {
    final sz = parsedSizes();
    final priced = sz.map((s) => s['price'] as double).where((p) => p > 0);
    return {
      'name': name.text.trim(),
      'category': category.text.trim().isEmpty ? null : category.text.trim(),
      'price': priced.isNotEmpty ? priced.reduce((a, b) => a < b ? a : b) : parseMenuPrice(price.text),
      'sizes': sz,
      'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
      'description': description,
      'imageUrl': imageUrl,
      'sampleCatalogId': sampleCatalogId,
      'sampleCatalogName': sampleCatalogName,
      'existingProductId': null,
      'existingProductName': existingProductName,
      'productType': type,
      'billing': type == 'Service' ? billing : 'Flat',
      'sessionCount': type == 'Service' && billing == 'PerSession'
          ? int.tryParse(sessions.text.trim()) ?? 0
          : 0,
      'toppingFor': type == 'Topping' ? parseNameList(toppingFor.text) : const <String>[],
      'comboItems': type == 'Combo' ? parseComboItems(comboItems.text) : const [],
    };
  }

  void dispose() {
    name.dispose();
    category.dispose();
    price.dispose();
    sizes.dispose();
    unit.dispose();
    sessions.dispose();
    toppingFor.dispose();
    comboItems.dispose();
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
    final flagged = [
      for (final r in chosen)
        if (r.warnings().isNotEmpty) '${r.name.text.trim()}: ${r.warnings().map(tr).join('; ')}',
    ];
    if (flagged.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('${flagged.length} món cần kiểm tra giá')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(child: Text(flagged.map((s) => '• $s').join('\n'))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Sửa lại'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn tạo'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
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
    final toppingGroups = (d['toppingGroupsCreated'] as num?) ?? 0;
    final toppingLinks = (d['toppingLinksCreated'] as num?) ?? 0;
    final combos = (d['combosCreated'] as num?) ?? 0;
    NotificationOverlayManager().showSuccess(
      title: tr('Đã tạo ${d['productsCreated'] ?? 0} món'),
      message: tr('${d['categoriesCreated'] ?? 0} nhóm mới · ${d['variantsCreated'] ?? 0} size') +
          (combos > 0 ? tr(' · $combos combo') : '') +
          (toppingGroups > 0 || toppingLinks > 0
              ? tr(' · $toppingGroups nhóm topping gắn vào $toppingLinks món')
              : '') +
          (skipped > 0 ? tr(' · bỏ qua $skipped món') : ''),
    );
    final notes = [
      ...((d['warnings'] as List?) ?? const []).map((e) => '$e'),
      ...((d['skipped'] as List?) ?? const []).map((e) => '${tr('Bỏ qua')}: $e'),
    ];
    if (notes.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Lưu ý sau khi tạo')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(child: Text(notes.map((s) => '• $s').join('\n'))),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu'))),
          ],
        ),
      );
      if (!mounted) return;
    }
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
              tr('Kiểm tra lại trước khi tạo: loại hàng, đơn vị, giá. Size ghi dạng «M 30.000; L 38k». '
                  'Topping được gom thành nhóm topping và gắn vào các nhóm / món ghi ở «Gắn vào». '
                  'Món đã có trong cửa hàng được bỏ chọn sẵn.'),
              style: TextStyle(color: SboxColors.slate700, fontSize: 13),
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
                              backgroundColor: SboxColors.textSecondary,
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
                  color: SboxColors.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
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
    final hasSizes = r.parsedSizes().any((s) => (s['price'] as num) > 0);
    final warnings = r.include ? r.warnings() : const <String>[];
    return Card(
      color: r.include ? null : SboxColors.slate100,
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
                          color: SboxColors.slate200,
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
                        width: 150,
                        child: DropdownButtonFormField<String>(
                          initialValue: r.type,
                          isExpanded: true,
                          decoration: deco('Loại'),
                          items: [
                            for (final e in menuProductTypes.entries)
                              DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
                          ],
                          onChanged: (v) => setState(() => r.type = v ?? 'Goods'),
                        ),
                      ),
                      SizedBox(width: 90, child: TextField(controller: r.unit, decoration: deco('Đơn vị'))),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: r.price,
                          keyboardType: TextInputType.number,
                          // Có size thì giá món = size rẻ nhất.
                          enabled: !hasSizes,
                          onChanged: (_) => setState(() {}),
                          decoration: deco(hasSizes ? 'Giá (theo size)' : 'Giá'),
                        ),
                      ),
                      if (menuTypeHasSizes(r.type))
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: r.sizes,
                            onChanged: (_) => setState(() {}),
                            decoration: deco('Size (tùy chọn)'),
                          ),
                        ),
                      if (r.type == 'Service')
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: r.billing,
                            isExpanded: true,
                            decoration: deco('Tính tiền'),
                            items: [
                              for (final e in menuBillingModes.entries)
                                DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
                            ],
                            onChanged: (v) => setState(() => r.billing = v ?? 'Flat'),
                          ),
                        ),
                      if (r.type == 'Service' && r.billing == 'PerSession')
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: r.sessions,
                            keyboardType: TextInputType.number,
                            decoration: deco('Số buổi'),
                          ),
                        ),
                      if (r.type == 'Topping')
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: r.toppingFor,
                            decoration: deco('Gắn vào (nhóm / món, cách nhau dấu phẩy)').copyWith(
                              hintText: tr('Để trống = mọi món trong lần nhập này'),
                            ),
                          ),
                        ),
                      if (r.type == 'Combo')
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: r.comboItems,
                            decoration: deco('Gồm các món').copyWith(hintText: tr('Cơm gà x1; Trà đá x1')),
                          ),
                        ),
                    ],
                  ),
                  if (warnings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        warnings.map(tr).join(' · '),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC62828), fontWeight: FontWeight.w600),
                      ),
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
                              : SboxColors.slate700,
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
