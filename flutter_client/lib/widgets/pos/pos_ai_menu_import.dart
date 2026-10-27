import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/image_compress.dart';
import '../notification_overlay.dart';
import 'pos_product_image.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Chụp / chọn ảnh menu hoặc file Excel / CSV → AI (Gemini) đọc tên món, nhóm, giá, size, gợi ý ảnh catalog mẫu
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

const _priceSuffix = r'(k|nghìn|nghin|ngàn|ngan|tr|triệu|trieu)';
final _singlePrice = RegExp('^(\\d+(?:[.,]\\d+)*)$_priceSuffix?(\\d{1,3})?\$');

/// «25.000» / «25,000» / «1.234.567» = phân cách nghìn; «25.5» / «1,5» = thập phân.
double? parseMenuNumber(String s) {
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(s) && !(s.contains('.') && s.contains(','))) {
    return double.tryParse(s.replaceAll(RegExp(r'[.,]'), ''));
  }
  final dec = math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
  if (dec < 0) return double.tryParse(s);
  final intPart = s.substring(0, dec).replaceAll(RegExp(r'[.,]'), '');
  final frac = s.substring(dec + 1);
  if (intPart.isEmpty || frac.isEmpty) return null;
  return double.tryParse('$intPart.$frac');
}

double? _parseSinglePrice(String s, String? fallbackSuffix) {
  final m = _singlePrice.firstMatch(s);
  if (m == null) return null;
  var n = parseMenuNumber(m.group(1)!);
  if (n == null) return null;
  var suffix = m.group(2);
  final tail = m.group(3);
  // «25-30k»: đầu thấp không ghi hậu tố → mượn hậu tố của đầu kia (chỉ khi là số nhỏ).
  if (suffix == null && fallbackSuffix != null && n < 1000) suffix = fallbackSuffix;
  if (tail != null) {
    if (suffix == null) return null;
    n = double.tryParse('${n.truncate()}.$tail') ?? n; // «1tr2» = 1,2 triệu; «2k5» = 2,5 nghìn
  }
  final mult = suffix == null
      ? 1
      : (suffix == 'tr' || suffix == 'triệu' || suffix == 'trieu')
          ? 1000000
          : 1000;
  return n * mult;
}

/// Giá gõ trên màn xem trước (cùng quy tắc với máy chủ): "35.000" → 35000, "35k" / "35 nghìn" → 35000,
/// "1,2tr" / "1tr2" → 1200000, "25-30k" → 25000 (giá thấp), "25.5" → 25,5 (cảnh báo giá dưới 1.000đ).
double parseMenuPrice(String s) {
  var t = s.toLowerCase().trim();
  final slash = t.indexOf('/');
  if (slash > 0) t = t.substring(0, slash); // «35k/ly»
  for (final w in const ['vnđ', 'vnd', 'đồng', '₫', '+']) {
    t = t.replaceAll(w, '');
  }
  t = t.replaceAll(RegExp(r'\s*(đến|tới|~|–|—)\s*'), '-');
  t = t.replaceAll(RegExp(r'\s'), '');
  t = t.replaceAll(RegExp(r'(?<=\d)[đd](?=$|-)'), '');
  final parts = t.split('-').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 0;
  final lastSuffix = parts.length > 1 ? _singlePrice.firstMatch(parts.last)?.group(2) : null;
  return _parseSinglePrice(parts.first, lastSuffix) ?? 0;
}

const _pricePattern =
    '[0-9][0-9.,]*\\s*$_priceSuffix?[0-9]{0,3}(?:\\s*[-~]\\s*[0-9][0-9.,]*\\s*$_priceSuffix?[0-9]{0,3})?\\s*(?:đ|vnđ|vnd|₫)?';

/// "M 30.000; L 38k" → [{name: M, price: 30000}, {name: L, price: 38000}].
/// Size không ghi giá («XL») vẫn giữ với giá 0 để báo người dùng (server lấy giá món).
List<Map<String, dynamic>> parseMenuSizes(String text) {
  final out = <Map<String, dynamic>>[];
  final re = RegExp('^\\s*(.+?)\\s+($_pricePattern)\\s*\$', caseSensitive: false);
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
List<String> parseNameList(String text) =>
    text.split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

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

/// Cảnh báo một dòng trước khi tạo: chưa có giá, size thiếu giá, giá nghi thiếu «nghìn» (dưới 1.000đ).
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
  if (!useSizes && price > 0 && price < 1000) {
    out.add('Giá dưới 1.000đ — có thiếu «k» / «nghìn» không?');
  }
  if (useSizes && priced.isNotEmpty) {
    final missing = sizes.where((s) => (s['price'] as num) <= 0).map((s) => s['name']).toList();
    if (missing.isNotEmpty) {
      out.add('Size ${missing.join(', ')} chưa có giá — sẽ lấy giá size rẻ nhất');
    }
    final low = sizes
        .where((s) => (s['price'] as num) > 0 && (s['price'] as num) < 1000)
        .map((s) => s['name'])
        .toList();
    if (low.isNotEmpty) {
      out.add('Size ${low.join(', ')} giá dưới 1.000đ — có thiếu «k» / «nghìn» không?');
    }
  }
  return out;
}

/// Khóa so trùng dòng: chữ thường + gộp khoảng trắng (giữ dấu — «Bánh mì bơ» ≠ «Bánh mì bò»).
String _rowKey(String name, String category) =>
    '${name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}|${category.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

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
        sessions =
            TextEditingController(text: ((j['sessionCount'] as num?) ?? 0) > 0 ? '${j['sessionCount']}' : ''),
        toppingFor =
            TextEditingController(text: ((j['toppingFor'] as List?) ?? const []).map((e) => '$e').join(', ')),
        comboItems = TextEditingController(text: comboItemsText(j['comboItems'])),
        description = j['description']?.toString(),
        imageUrl = j['imageUrl']?.toString(),
        sampleCatalogId = j['sampleCatalogId']?.toString(),
        sampleCatalogName = j['sampleCatalogName']?.toString(),
        sampleCostPrice = (j['sampleCostPrice'] as num?)?.toDouble(),
        sampleVatRate = (j['sampleVatRate'] as num?)?.toDouble(),
        sampleUnit = j['sampleUnit']?.toString(),
        existingProductName = j['existingProductName']?.toString(),
        possibleDuplicateName = j['possibleDuplicateName']?.toString(),
        scanNotes = ((j['warnings'] as List?) ?? const []).map((e) => '$e').toList();

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
  String? sampleCatalogId;
  String? sampleCatalogName;
  double? sampleCostPrice;
  double? sampleVatRate;
  String? sampleUnit;
  final String? existingProductName;
  final String? possibleDuplicateName;

  /// Lưu ý máy chủ ghi khi đọc (giá đã nhân nghìn, khoảng giá, «thời giá», có thể trùng…).
  final List<String> scanNotes;

  static final _money = NumberFormat.decimalPattern('vi');
  static String _fmt(num v) => v <= 0 ? '' : _money.format(v);
  static String money(num v) => _money.format(v);

  static String _sizesText(dynamic raw) {
    if (raw is! List) return '';
    return raw
        .whereType<Map>()
        .map((s) => '${s['name']} ${_fmt((s['price'] as num?) ?? 0)}'.trim())
        .join('; ');
  }

  String get key => _rowKey(name.text, category.text);

  List<Map<String, dynamic>> parsedSizes() => menuTypeHasSizes(type) ? parseMenuSizes(sizes.text) : const [];

  List<String> warnings() => menuRowWarnings(
        type: type,
        price: parseMenuPrice(price.text),
        sizes: parsedSizes(),
      );

  bool get needsReview => warnings().isNotEmpty || scanNotes.isNotEmpty || possibleDuplicateName != null;

  /// Bỏ liên kết món mẫu: không chép ảnh, giá vốn, VAT của mẫu.
  void unlinkSample() {
    sampleCatalogId = null;
    sampleCatalogName = null;
    sampleCostPrice = null;
    sampleVatRate = null;
    sampleUnit = null;
    imageUrl = null;
  }

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
      'sessionCount':
          type == 'Service' && billing == 'PerSession' ? int.tryParse(sessions.text.trim()) ?? 0 : 0,
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

/// Ảnh menu đã chọn: [scanned] = đã gửi AI đọc xong; [failed] = lần đọc trước lỗi (đọc lại riêng ảnh này).
class _MenuImage {
  _MenuImage(this.bytes, this.name, {this.heic = false});
  final Uint8List bytes;
  final String name;
  final bool heic;
  bool scanned = false;
  bool failed = false;

  bool get pending => !scanned || failed;
}

class _PosAiMenuImportPage extends StatefulWidget {
  const _PosAiMenuImportPage({required this.api});
  final ApiService api;

  @override
  State<_PosAiMenuImportPage> createState() => _PosAiMenuImportPageState();
}

class _PosAiMenuImportPageState extends State<_PosAiMenuImportPage> {
  static const _maxImages = 8;

  /// Máy chủ nhận tối đa 12 MB mỗi ảnh.
  static const _maxImageBytes = 12 * 1024 * 1024;
  final _images = <_MenuImage>[];
  final _rows = <_MenuRow>[];
  bool _scanning = false;
  bool _preparing = false;
  bool _importing = false;
  bool _onlyReview = false;

  /// Lỗi đọc menu hiện ngay trên trang (thông báo nổi có thể bị che bởi trang toàn màn hình).
  String? _scanError;

  /// Lưu ý cả lần đọc (ảnh lỗi, món sai định dạng…).
  List<String> _scanNotes = const [];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _busy => _scanning || _preparing || _importing;

  Future<List<({Uint8List bytes, String name})>?> _pickRawImages() async {
    Future<List<({Uint8List bytes, String name})>?> gallery() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null) return null;
      return [
        for (final f in result.files)
          if (f.bytes != null) (bytes: f.bytes!, name: f.name),
      ];
    }

    if (kIsWeb) return gallery();
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(tr('Chụp ảnh')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(tr('Chọn từ thư viện')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    if (source == 'gallery') return gallery();
    // Chữ trên menu cần độ phân giải cao hơn ảnh sản phẩm.
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2200,
      maxHeight: 2200,
      imageQuality: 85,
    );
    if (photo == null) return null;
    return [(bytes: await photo.readAsBytes(), name: photo.name)];
  }

  Future<void> _addImages() async {
    final room = _maxImages - _images.length;
    if (room <= 0) {
      NotificationOverlayManager().showWarning(
        title: tr('Đã đủ $_maxImages ảnh'),
        message: tr('Tạo hàng cho các ảnh này trước, hoặc xóa bớt ảnh đã đọc rồi thêm ảnh mới.'),
      );
      return;
    }
    var picked = await _pickRawImages();
    if (picked == null || picked.isEmpty || !mounted) return;
    if (picked.length > room) {
      NotificationOverlayManager().showWarning(
        title: tr('Chỉ thêm được $room ảnh'),
        message: tr('Tối đa $_maxImages ảnh mỗi lần — đã bỏ ${picked.length - room} ảnh. '
            'Đọc và tạo hàng xong, xóa ảnh cũ rồi thêm phần menu còn lại.'),
      );
      picked = picked.take(room).toList();
    }
    setState(() => _preparing = true);
    final rejected = <String>[];
    final heicNames = <String>[];
    final added = <_MenuImage>[];
    for (final p in picked) {
      // Nén + xoay theo EXIF trên isolate nền.
      PreparedImage prepared;
      try {
        prepared = await prepareImageForUpload(p.bytes, maxEdge: 2200, jpegQuality: 85);
      } catch (_) {
        prepared = (bytes: p.bytes, decoded: false);
      }
      if (prepared.decoded) {
        added.add(_MenuImage(prepared.bytes, jpegFileName(p.name)));
      } else if (looksLikeHeic(p.bytes) && p.bytes.length <= _maxImageBytes) {
        // Máy chủ / AI đọc được HEIC dù máy này không xem trước được.
        added.add(_MenuImage(p.bytes, p.name, heic: true));
        heicNames.add(p.name);
      } else {
        rejected.add(p.name);
      }
    }
    if (!mounted) return;
    setState(() {
      _images.addAll(added);
      _preparing = false;
    });
    if (rejected.isNotEmpty) {
      NotificationOverlayManager().showError(
        title: tr('Không đọc được ảnh'),
        message: tr('${rejected.join(', ')}: không mở được ảnh (định dạng lạ hoặc ảnh quá lớn) — '
            'chụp lại hoặc lưu ảnh dạng JPG / PNG rồi thử lại.'),
      );
    } else if (heicNames.isNotEmpty) {
      NotificationOverlayManager().showInfo(
        title: tr('Ảnh HEIC'),
        message: tr('${heicNames.join(', ')}: máy không xem trước được ảnh HEIC, vẫn gửi cho AI đọc. '
            'Nếu AI báo lỗi, chuyển ảnh sang JPG rồi thử lại.'),
      );
    }
  }

  /// Đọc ảnh chưa đọc / đọc lỗi; [all] = đọc lại tất cả (đã xác nhận xóa danh sách).
  Future<void> _scanImages({bool all = false}) async {
    final targets = all ? _images.toList() : _images.where((i) => i.pending).toList();
    if (targets.isEmpty) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    final res = await widget.api.scanPosMenuAi([
      for (final i in targets) (bytes: i.bytes, name: i.name),
    ]);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (res['isSuccess'] != true) {
      _showScanError(res);
      return;
    }
    final data = res['data'] as Map? ?? const {};
    final failed =
        ((data['failedParts'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toSet();
    setState(() {
      for (var i = 0; i < targets.length; i++) {
        targets[i].scanned = true;
        targets[i].failed = failed.contains(i);
      }
      if (all) {
        final old = _rows.toList();
        _rows.clear();
        // Gỡ controller sau khung hình (ô nhập cũ còn gắn tới khi dựng lại).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final r in old) {
            r.dispose();
          }
        });
      }
    });
    _appendRows(data);
  }

  Future<void> _rescanAll() async {
    if (_rows.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Đọc lại tất cả ảnh?')),
          content: Text(tr('Danh sách ${_rows.length} món hiện tại (kể cả phần đã sửa) sẽ bị xóa '
              'và thay bằng kết quả đọc mới.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đọc lại'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _scanImages(all: true);
  }

  Future<void> _pickSheet() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    if (f.name.toLowerCase().endsWith('.xls')) {
      NotificationOverlayManager().showError(
        title: tr('Chưa đọc được file .xls'),
        message: tr('Mở file bằng Excel, chọn Lưu thành (Save As) dạng .xlsx rồi chọn lại.'),
      );
      return;
    }
    if (f.bytes == null) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    final res = await widget.api.scanPosMenuSheetAi(f.bytes!, f.name);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (res['isSuccess'] != true) {
      _showScanError(res);
      return;
    }
    _appendRows(res['data'] as Map? ?? const {});
  }

  void _showScanError(Map<String, dynamic> res) {
    final msg = res['message']?.toString() ?? tr('Vui lòng thử lại sau');
    setState(() => _scanError = msg);
    NotificationOverlayManager().showError(
      title: tr('Không đọc được menu'),
      message: msg,
    );
  }

  /// Thêm món vừa đọc vào cuối danh sách; món đã có trong danh sách (cùng tên + nhóm) giữ dòng cũ (có thể đã sửa).
  void _appendRows(Map data) {
    final items = (data['items'] as List?) ?? const [];
    final keys = _rows.map((r) => r.key).toSet();
    var added = 0;
    var dup = 0;
    setState(() {
      _scanNotes = ((data['warnings'] as List?) ?? const []).map((e) => '$e').toList();
      for (final e in items.whereType<Map>()) {
        final row = _MenuRow(Map<String, dynamic>.from(e));
        if (!keys.add(row.key)) {
          row.dispose();
          dup++;
          continue;
        }
        _rows.add(row);
        added++;
      }
    });
    if (dup > 0 || _rows.length > added) {
      NotificationOverlayManager().showInfo(
        title: tr('Đã thêm $added món'),
        message: dup > 0
            ? tr('Bỏ $dup món đã có trong danh sách (giữ dòng bạn đã sửa).')
            : tr('Thêm vào cuối danh sách.'),
      );
    }
  }

  Future<void> _import() async {
    final chosen = _rows.where((r) => r.include && r.name.text.trim().isNotEmpty).toList();
    if (chosen.isEmpty) return;
    final flagged = [
      for (final r in chosen)
        if (r.warnings().isNotEmpty || r.possibleDuplicateName != null)
          '${r.name.text.trim()}: ${[
            ...r.warnings().map(tr),
            if (r.possibleDuplicateName != null) tr('có thể trùng hàng «${r.possibleDuplicateName}»'),
          ].join('; ')}',
    ];
    if (flagged.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('${flagged.length} món cần kiểm tra')),
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

  void _removeRow(_MenuRow r) {
    setState(() => _rows.remove(r));
    // Gỡ controller sau khung hình để ô đang focus không lỗi.
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final selected = _rows.where((r) => r.include).length;
    final reviewCount = _rows.where((r) => r.needsReview).length;
    final visible = _onlyReview ? _rows.where((r) => r.needsReview).toList() : _rows;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Tạo hàng từ ảnh menu / Excel (AI)')),
        actions: [
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _busy || selected == 0 ? null : _import,
                icon: _importing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(tr('Tạo $selected món')),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSourceCard(),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              tr('Kiểm tra lại trước khi tạo: loại hàng, đơn vị, giá. Size ghi dạng «M 30.000; L 38k». '
                  'Topping được gom thành nhóm topping và gắn vào các nhóm / món ghi ở «Gắn vào». '
                  'Món đã có trong cửa hàng được bỏ chọn sẵn.'),
              style: const TextStyle(color: SboxColors.slate700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(tr('Đã chọn $selected / ${_rows.length} món'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () => setState(() {
                    for (final r in _rows) {
                      r.include = true;
                    }
                  }),
                  child: Text(tr('Chọn tất cả')),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    for (final r in _rows) {
                      r.include = false;
                    }
                  }),
                  child: Text(tr('Bỏ chọn tất cả')),
                ),
                FilterChip(
                  label: Text(tr('Chỉ món cần kiểm tra ($reviewCount)')),
                  selected: _onlyReview,
                  onSelected: (v) => setState(() => _onlyReview = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in visible) _buildRow(r),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(tr('Không có món nào cần kiểm tra.'))),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageTile(int i) {
    final im = _images[i];
    final badge = im.failed
        ? const CircleAvatar(
            radius: 10,
            backgroundColor: SboxColors.danger,
            child: Icon(Icons.priority_high, size: 13, color: Colors.white))
        : im.scanned
            ? const CircleAvatar(
                radius: 10,
                backgroundColor: SboxColors.success,
                child: Icon(Icons.check, size: 13, color: Colors.white))
            : null;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            im.bytes,
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 84,
              height: 84,
              color: SboxColors.slate200,
              alignment: Alignment.center,
              child: Text(im.heic ? 'HEIC' : tr('Ảnh'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        if (badge != null) Positioned(left: 2, bottom: 2, child: badge),
        Positioned(
          right: 0,
          top: 0,
          child: InkWell(
            onTap: _busy ? null : () => setState(() => _images.removeAt(i)),
            child: const CircleAvatar(
                radius: 11,
                backgroundColor: SboxColors.textSecondary,
                child: Icon(Icons.close, size: 14, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceCard() {
    final pending = _images.where((i) => i.pending).length;
    final failed = _images.where((i) => i.failed).length;
    final String scanLabel;
    if (_scanning) {
      scanLabel = tr('AI đang đọc… (có thể mất 30–90 giây)');
    } else if (pending > 0) {
      scanLabel = _rows.isEmpty && failed == 0 ? tr('Đọc menu bằng AI') : tr('Đọc $pending ảnh mới / lỗi');
    } else {
      scanLabel = tr('Đọc lại tất cả ảnh');
    }
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
                for (var i = 0; i < _images.length; i++) _buildImageTile(i),
                if (_images.length < _maxImages)
                  InkWell(
                    onTap: _busy ? null : _addImages,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border.all(color: PosTheme.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _preparing
                          ? const Center(
                              child: SizedBox(
                                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                          : const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
              ],
            ),
            if (_preparing) ...[
              const SizedBox(height: 6),
              Text(tr('Đang chuẩn bị ảnh (nén, xoay đúng chiều)…'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
            ],
            if (failed > 0) ...[
              const SizedBox(height: 6),
              Text(
                  tr('$failed ảnh đọc lỗi (dấu !) — bấm «Đọc $pending ảnh mới / lỗi» để đọc lại riêng các ảnh đó.'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.danger)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      _busy || _images.isEmpty ? null : () => pending > 0 ? _scanImages() : _rescanAll(),
                  icon: _scanning
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(pending > 0 || _rows.isEmpty ? Icons.auto_awesome : Icons.refresh),
                  label: Text(scanLabel),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickSheet,
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(tr('Đọc file Excel / CSV bằng AI')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('File Excel lộn xộn (tự làm, xuất từ phần mềm khác) → AI đọc ra món. '
                  'File đã có cột rõ ràng / rất nhiều dòng: dùng «Nhập Excel» thường.'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
            ),
            if (_scanNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              _noteBox(_scanNotes, error: false),
            ],
            if (_scanError != null) ...[
              const SizedBox(height: 10),
              _noteBox(['${tr('Không đọc được menu')}: $_scanError'], error: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noteBox(List<String> lines, {required bool error}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? SboxColors.dangerSoft : SboxColors.warningSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: error ? const Color(0xFFEF9A9A) : const Color(0xFFFCD34D)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(error ? Icons.error_outline : Icons.info_outline,
                color: error ? const Color(0xFFC62828) : SboxColors.warningText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lines.map((s) => lines.length > 1 ? '• $s' : s).join('\n'),
                style: TextStyle(color: error ? const Color(0xFFB71C1C) : SboxColors.warningText),
              ),
            ),
          ],
        ),
      );

  Widget _buildRow(_MenuRow r) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: tr(label),
          isDense: true,
          border: const OutlineInputBorder(),
        );
    final hasSizes = r.parsedSizes().any((s) => (s['price'] as num) > 0);
    final warnings = r.include ? r.warnings() : const <String>[];
    final sampleParts = <String>[
      if (r.sampleCostPrice != null) tr('giá vốn ${_MenuRow.money(r.sampleCostPrice!)}'),
      if (r.sampleVatRate != null) 'VAT ${_MenuRow.money(r.sampleVatRate!)}%',
      if (r.sampleUnit != null) tr('ĐVT ${r.sampleUnit}'),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final thumb = narrow ? 40.0 : 56.0;
    return Card(
      key: ObjectKey(r),
      color: r.include ? null : SboxColors.slate100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: r.include,
              onChanged: (v) => setState(() => r.include = v ?? false),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Column(
                children: [
                  r.imageUrl == null
                      ? Container(
                          width: thumb,
                          height: thumb,
                          color: SboxColors.slate200,
                          child: const Icon(Icons.image_not_supported_outlined, size: 20),
                        )
                      : PosProductImage(imageUrl: r.imageUrl, size: thumb),
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
                  LayoutBuilder(builder: (context, c) {
                    // Điện thoại: ô nhập chiếm cả / nửa dòng thay vì độ rộng cố định.
                    double w(double wide, {bool half = false}) =>
                        narrow ? (half ? (c.maxWidth - 8) / 2 : c.maxWidth) : math.min(wide, c.maxWidth);
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                            width: w(240),
                            child: TextField(
                              controller: r.name,
                              onChanged: (_) => setState(() {}),
                              decoration: deco('Tên món'),
                            )),
                        SizedBox(
                            width: w(170, half: true),
                            child: TextField(controller: r.category, decoration: deco('Nhóm'))),
                        SizedBox(
                          width: w(150, half: true),
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
                        SizedBox(
                            width: w(90, half: true),
                            child: TextField(controller: r.unit, decoration: deco('Đơn vị'))),
                        SizedBox(
                          width: w(120, half: true),
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
                            width: w(240),
                            child: TextField(
                              controller: r.sizes,
                              onChanged: (_) => setState(() {}),
                              decoration: deco('Size (tùy chọn)'),
                            ),
                          ),
                        if (r.type == 'Service')
                          SizedBox(
                            width: w(160, half: true),
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
                            width: w(90, half: true),
                            child: TextField(
                              controller: r.sessions,
                              keyboardType: TextInputType.number,
                              decoration: deco('Số buổi'),
                            ),
                          ),
                        if (r.type == 'Topping')
                          SizedBox(
                            width: w(320),
                            child: TextField(
                              controller: r.toppingFor,
                              decoration: deco('Gắn vào (nhóm / món, cách nhau dấu phẩy)').copyWith(
                                hintText: tr('Để trống = mọi món trong lần nhập này'),
                              ),
                            ),
                          ),
                        if (r.type == 'Combo')
                          SizedBox(
                            width: w(320),
                            child: TextField(
                              controller: r.comboItems,
                              decoration: deco('Gồm các món').copyWith(hintText: tr('Cơm gà x1; Trà đá x1')),
                            ),
                          ),
                      ],
                    );
                  }),
                  if (warnings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        warnings.map(tr).join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFC62828), fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (r.scanNotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${tr('Lưu ý khi đọc')}: ${r.scanNotes.join(' · ')}',
                        style: const TextStyle(fontSize: 12, color: SboxColors.warningText),
                      ),
                    ),
                  if (r.existingProductName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        tr('Đã có hàng «${r.existingProductName}»'),
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  if (r.sampleCatalogName != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          [
                            tr('Theo món mẫu «${r.sampleCatalogName}»'),
                            ...sampleParts,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: SboxColors.slate700),
                        ),
                        TextButton(
                          onPressed: () => setState(r.unlinkSample),
                          child: Text(tr('Bỏ liên kết mẫu'), style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Xóa dòng'),
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _busy ? null : () => _removeRow(r),
            ),
          ],
        ),
      ),
    );
  }
}
