import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/pos_ai_invoice_api.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/image_compress.dart';
import '../notification_overlay.dart';
import 'pos_ai_menu_import.dart' show parseMenuNumber, parseMenuPrice;
import 'package:sbox_pos/l10n/app_tr.dart';

/// Phiếu nhập vừa tạo từ ảnh hóa đơn NCC.
class PosAiInvoiceResult {
  const PosAiInvoiceResult({required this.receiptId, required this.receiptNo, required this.status});
  final String receiptId;
  final String receiptNo;

  /// `Draft` (phiếu tạm) hoặc `Completed` (đã nhập kho).
  final String status;
  bool get isDraft => status == 'Draft';
}

/// Chụp 1–4 ảnh hóa đơn nhà cung cấp → AI đọc NCC, số / ngày, dòng hàng → xem trước, sửa (chọn hàng, SL, ĐVT, giá)
/// → tạo phiếu nhập tạm (mặc định) hoặc nhập kho luôn. Trả phiếu đã tạo, `null` nếu bỏ.
Future<PosAiInvoiceResult?> showPosAiInvoiceImport(BuildContext context) =>
    Navigator.of(context).push<PosAiInvoiceResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _PosAiInvoicePage()),
    );

final _moneyFmt = NumberFormat.decimalPattern('vi');
final _qtyFmt = NumberFormat('#,##0.###', 'vi');
String _money(num v) => _moneyFmt.format(v.round());
String _qty(num v) => _qtyFmt.format(v);

/// SL gõ tay: «2,5» = 2,5; «1.000» = 1000; «12 thùng» = 12.
double _parseQty(String s) {
  final m = RegExp(r'\d+(?:[.,]\d+)*').firstMatch(s);
  return m == null ? 0 : (parseMenuNumber(m.group(0)!) ?? 0);
}

/// Khóa ĐVT bỏ dấu / hoa thường (khớp cách so phía máy chủ ở mức đơn giản).
String _unitKey(String? s) {
  const from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in (s ?? '').toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    if (RegExp(r'[a-z0-9]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

const _vatChoices = <double>[0, 5, 8, 10];

class _ProductRef {
  const _ProductRef(this.id, this.name, this.code, this.baseUnit, [this.units = const {}]);
  final String id;
  final String name;
  final String? code;
  final String? baseUnit;

  /// ĐVT quy đổi đã khai báo (khóa ĐVT → tên, hệ số) khi danh sách hàng trả kèm.
  final Map<String, ({String name, double rate})> units;

  static _ProductRef? fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final units = <String, ({String name, double rate})>{};
    for (final u in ((j['units'] as List?) ?? const []).whereType<Map>()) {
      final rate = (u['conversionRate'] as num?)?.toDouble() ?? 0;
      final name = (u['unitName'] ?? '').toString();
      if (u['isBaseUnit'] == true || rate <= 0 || name.isEmpty) continue;
      units[_unitKey(name)] = (name: name, rate: rate);
    }
    return _ProductRef(id, (j['name'] ?? '').toString(), (j['code'] ?? j['productCode'])?.toString(),
        (j['baseUnit'] ?? j['baseUnitName'])?.toString(), units);
  }
}

/// Một dòng hóa đơn trên màn xem trước.
class _InvRow {
  _InvRow.fromJson(Map<String, dynamic> j)
      : invoiceName = (j['name'] ?? '').toString(),
        invoiceUnit = (j['unit'] ?? '').toString(),
        productId = j['matchedProductId']?.toString(),
        productName = j['matchedProductName']?.toString(),
        matchedBy = j['matchedBy']?.toString(),
        baseUnit = j['baseUnitName']?.toString(),
        unitStatus = (j['unitStatus'] ?? 'none').toString(),
        printedTotal = (j['lineTotal'] as num?)?.toDouble() ?? 0,
        serverNotes = ((j['warnings'] as List?) ?? const []).map((e) => '$e').toList(),
        possible = ((j['possibleMatches'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => _ProductRef.fromJson(Map<String, dynamic>.from(e)))
            .whereType<_ProductRef>()
            .toList(),
        vatExempt = j['vatExempt'] == true,
        vatRate = (j['vatRate'] as num?)?.toDouble() ?? 0,
        qty = TextEditingController(text: _qty((j['qty'] as num?) ?? 0)),
        unit = TextEditingController(text: (j['unitName'] ?? j['unit'] ?? '').toString()),
        price = TextEditingController(text: _money((j['unitPrice'] as num?) ?? 0)),
        discount = TextEditingController(
            text: ((j['discount'] as num?) ?? 0) > 0 ? _money((j['discount'] as num?) ?? 0) : ''),
        factor = TextEditingController(
            text: ((j['unitFactor'] as num?) ?? 1) != 1 && j['unitStatus'] == 'remembered'
                ? _qty((j['unitFactor'] as num?) ?? 1)
                : ''),
        unitInfoFactor = (j['unitFactor'] as num?)?.toDouble() ?? 1,
        newName = TextEditingController(text: (j['name'] ?? '').toString());

  /// Dòng người dùng tự thêm (AI bỏ sót).
  _InvRow.blank()
      : invoiceName = '',
        invoiceUnit = '',
        productId = null,
        productName = null,
        matchedBy = null,
        baseUnit = null,
        unitStatus = 'none',
        printedTotal = 0,
        serverNotes = const [],
        possible = const [],
        vatExempt = false,
        vatRate = 0,
        qty = TextEditingController(text: '1'),
        unit = TextEditingController(),
        price = TextEditingController(),
        discount = TextEditingController(),
        factor = TextEditingController(),
        unitInfoFactor = 1,
        newName = TextEditingController();

  final String invoiceName;
  final String invoiceUnit;
  String? productId;
  String? productName;
  String? matchedBy;
  String? baseUnit;

  /// base / unit / remembered / unknown / none (chưa khớp) / check (người dùng đổi hàng — máy chủ kiểm ĐVT khi tạo).
  String unitStatus;
  final double printedTotal;
  List<String> serverNotes;
  final List<_ProductRef> possible;
  bool vatExempt;
  double vatRate;
  bool createNew = false;
  double unitInfoFactor;
  final TextEditingController qty;
  final TextEditingController unit;
  final TextEditingController price;
  final TextEditingController discount;
  final TextEditingController factor;
  final TextEditingController newName;

  double get qtyV => _parseQty(qty.text);
  double get priceV => parseMenuPrice(price.text);
  double get discountV => parseMenuPrice(discount.text);
  double get factorV => _parseQty(factor.text);
  double get vatV => vatExempt ? 0 : vatRate;
  String get displayName => invoiceName.isNotEmpty ? invoiceName : tr('Dòng thêm tay');

  /// Thành tiền như in trên hóa đơn (SL × đơn giá − CK).
  double get gross => math.max(0, qtyV * priceV - discountV);

  /// Tiền hàng trước thuế + tiền thuế — cùng cách tính với phiếu nhập trên máy chủ.
  ({double net, double vat}) amounts(bool pricesIncludeVat) {
    var cost = priceV;
    if (pricesIncludeVat && vatV > 0 && cost > 0) cost = (cost / (1 + vatV / 100)).roundToDouble();
    final net = math.max(0.0, qtyV * cost - discountV);
    return (net: net, vat: vatExempt ? 0 : (net * vatV / 100).roundToDouble());
  }

  bool get hasProduct => productId != null || createNew;

  /// ĐVT khác ĐVT gốc mà hàng chưa khai báo (hoặc chưa biết) → hỏi hệ số quy đổi.
  bool get needsFactor {
    if (createNew || productId == null) return false;
    if (_unitKey(unit.text).isEmpty || _unitKey(unit.text) == _unitKey(baseUnit)) return false;
    return unitStatus == 'unknown' || unitStatus == 'remembered' || unitStatus == 'check';
  }

  List<String> localWarnings() => [
        if (!hasProduct) tr('Chưa chọn hàng — chọn hàng có sẵn hoặc bật «Tạo hàng mới»'),
        if (qtyV <= 0) tr('Số lượng phải lớn hơn 0'),
        if (priceV <= 0) tr('Chưa có đơn giá'),
        if (needsFactor && unitStatus == 'unknown' && factorV <= 0)
          tr('ĐVT «${unit.text.trim()}» chưa khai báo — nhập hệ số quy đổi hoặc sửa SL theo ĐVT gốc'),
        if (printedTotal > 0 && (gross - printedTotal).abs() > math.max(5, printedTotal * 0.002))
          tr('Thành tiền ${_money(gross)} đ khác hóa đơn ${_money(printedTotal)} đ'),
      ];

  Map<String, dynamic> toJson() => {
        'invoiceName': invoiceName.isNotEmpty ? invoiceName : (createNew ? newName.text.trim() : productName),
        'productId': createNew ? null : productId,
        'createProduct': createNew,
        'newProductName': createNew ? newName.text.trim() : null,
        'qty': qtyV,
        'unitName': unit.text.trim().isEmpty ? null : unit.text.trim(),
        'unitPrice': priceV,
        'discount': discountV,
        'vatRate': vatV,
        'vatExempt': vatExempt,
        'vatIncluded': false,
        'unitFactor': needsFactor && factorV > 0 ? factorV : 1,
        'remember': invoiceName.isNotEmpty,
        'invoiceUnit': invoiceUnit.isEmpty ? null : invoiceUnit,
      };

  void dispose() {
    qty.dispose();
    unit.dispose();
    price.dispose();
    discount.dispose();
    factor.dispose();
    newName.dispose();
  }
}

class _InvImage {
  _InvImage(this.bytes, this.name, {this.heic = false});
  final Uint8List bytes;
  final String name;
  final bool heic;
}

class _PosAiInvoicePage extends StatefulWidget {
  const _PosAiInvoicePage();

  @override
  State<_PosAiInvoicePage> createState() => _PosAiInvoicePageState();
}

class _PosAiInvoicePageState extends State<_PosAiInvoicePage> {
  static const _maxImages = 4;
  static const _maxImageBytes = 12 * 1024 * 1024;

  final _api = PosAiInvoiceApi();
  final _images = <_InvImage>[];
  final _rows = <_InvRow>[];
  bool _preparing = false;
  bool _scanning = false;
  bool _saving = false;
  bool _scanned = false;
  String? _scanError;
  List<String> _scanNotes = const [];

  // NCC
  List<Map<String, dynamic>> _suppliers = const [];
  String? _supplierId;
  String? _supplierName;
  String? _matchedBy;
  bool _createSupplier = false;
  final _supName = TextEditingController();
  final _supPhone = TextEditingController();
  final _supTax = TextEditingController();
  String? _supAddress;

  // Hóa đơn
  final _invoiceNo = TextEditingController();
  DateTime? _invoiceDate;
  bool _pricesIncludeVat = false;
  double? _printedSubtotal;
  double? _printedVat;
  double? _printedTotal;
  final _invoiceDiscount = TextEditingController();

  // Hoàn thành
  bool _complete = false;
  final _paid = TextEditingController();
  String _paymentMethod = 'Tiền mặt';

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in [_supName, _supPhone, _supTax, _invoiceNo, _invoiceDiscount, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _busy => _preparing || _scanning || _saving;

  // ─────────────────────────── Ảnh ───────────────────────────

  Future<List<({Uint8List bytes, String name})>?> _pickRaw() async {
    Future<List<({Uint8List bytes, String name})>?> gallery() async {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
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
              title: Text(tr('Chụp ảnh hóa đơn')),
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
    // Chữ nhỏ trên hóa đơn cần độ phân giải cao.
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (photo == null) return null;
    return [(bytes: await photo.readAsBytes(), name: photo.name)];
  }

  Future<void> _addImages() async {
    final room = _maxImages - _images.length;
    if (room <= 0) {
      NotificationOverlayManager().showWarning(
        title: tr('Đã đủ $_maxImages ảnh'),
        message: tr('Mỗi hóa đơn tối đa $_maxImages ảnh — xóa bớt ảnh rồi thêm ảnh khác.'),
      );
      return;
    }
    var picked = await _pickRaw();
    if (picked == null || picked.isEmpty || !mounted) return;
    if (picked.length > room) {
      NotificationOverlayManager().showWarning(
        title: tr('Chỉ thêm được $room ảnh'),
        message: tr('Mỗi hóa đơn tối đa $_maxImages ảnh — đã bỏ ${picked.length - room} ảnh.'),
      );
      picked = picked.take(room).toList();
    }
    setState(() => _preparing = true);
    final rejected = <String>[];
    final added = <_InvImage>[];
    for (final p in picked) {
      // Nén + xoay theo EXIF trên isolate nền.
      PreparedImage prepared;
      try {
        prepared = await prepareImageForUpload(p.bytes, maxEdge: 2400, jpegQuality: 88);
      } catch (_) {
        prepared = (bytes: p.bytes, decoded: false);
      }
      if (prepared.decoded) {
        added.add(_InvImage(prepared.bytes, jpegFileName(p.name)));
      } else if (looksLikeHeic(p.bytes) && p.bytes.length <= _maxImageBytes) {
        // Máy chủ / AI đọc được HEIC dù máy này không xem trước được.
        added.add(_InvImage(p.bytes, p.name, heic: true));
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
        message: tr('${rejected.join(', ')}: không mở được ảnh — chụp lại hoặc lưu dạng JPG / PNG rồi thử lại.'),
      );
    }
  }

  Future<void> _scan() async {
    if (_images.isEmpty) return;
    if (_rows.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Đọc lại hóa đơn?')),
          content: Text(tr('Các dòng hiện tại (kể cả phần đã sửa) sẽ bị thay bằng kết quả đọc mới.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đọc lại'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    final res = await _api.scan([for (final i in _images) (bytes: i.bytes, name: i.name, heic: i.heic)]);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (res['isSuccess'] != true) {
      final msg = res['message']?.toString() ?? tr('Vui lòng thử lại sau');
      setState(() => _scanError = msg);
      NotificationOverlayManager().showError(title: tr('Không đọc được hóa đơn'), message: msg);
      return;
    }
    _apply(Map<String, dynamic>.from(res['data'] as Map? ?? const {}));
    if (_suppliers.isEmpty) unawaited(_loadSuppliers());
  }

  Future<void> _loadSuppliers() async {
    final list = await _api.suppliers();
    if (mounted) setState(() => _suppliers = list);
  }

  void _apply(Map<String, dynamic> d) {
    final old = _rows.toList();
    final sup = Map<String, dynamic>.from(d['supplier'] as Map? ?? const {});
    final totals = Map<String, dynamic>.from(d['totals'] as Map? ?? const {});
    setState(() {
      _rows
        ..clear()
        ..addAll(((d['lines'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => _InvRow.fromJson(Map<String, dynamic>.from(e))));
      _scanNotes = ((d['warnings'] as List?) ?? const []).map((e) => '$e').toList();
      _supplierId = sup['matchedSupplierId']?.toString();
      _supplierName = sup['matchedSupplierName']?.toString();
      _matchedBy = sup['matchedBy']?.toString();
      _supName.text = (sup['name'] ?? '').toString();
      _supPhone.text = (sup['phone'] ?? '').toString();
      _supTax.text = (sup['taxCode'] ?? '').toString();
      _supAddress = sup['address']?.toString();
      _createSupplier = _supplierId == null && _supName.text.trim().isNotEmpty;
      _invoiceNo.text = (d['invoiceNo'] ?? '').toString();
      _invoiceDate = DateTime.tryParse((d['invoiceDate'] ?? '').toString());
      _pricesIncludeVat = d['pricesIncludeVat'] == true;
      _printedSubtotal = (totals['subtotal'] as num?)?.toDouble();
      _printedVat = (totals['vat'] as num?)?.toDouble();
      _printedTotal = (totals['total'] as num?)?.toDouble();
      final disc = (totals['discount'] as num?)?.toDouble() ?? 0;
      _invoiceDiscount.text = disc > 0 ? _money(disc) : '';
      _scanned = true;
    });
    // Gỡ controller sau khung hình (ô nhập cũ còn gắn tới khi dựng lại).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in old) {
        r.dispose();
      }
    });
  }

  // ─────────────────────────── Tổng ───────────────────────────

  ({double net, double vat, double total}) _totals() {
    var net = 0.0, vat = 0.0;
    for (final r in _rows) {
      final a = r.amounts(_pricesIncludeVat);
      net += a.net;
      vat += a.vat;
    }
    final disc = parseMenuPrice(_invoiceDiscount.text);
    return (net: net, vat: vat, total: math.max(0, net + vat - disc));
  }

  // ─────────────────────────── Tạo phiếu ───────────────────────────

  Future<void> _confirm() async {
    if (_rows.isEmpty) return;
    final blocking = <String>[
      for (var i = 0; i < _rows.length; i++)
        if (!_rows[i].hasProduct || _rows[i].qtyV <= 0)
          '${i + 1}. ${_rows[i].displayName}: ${_rows[i].localWarnings().first}',
    ];
    if (blocking.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Còn ${blocking.length} dòng chưa xong')),
          content: SizedBox(width: 420, child: SingleChildScrollView(child: Text(blocking.map((s) => '• $s').join('\n')))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Sửa lại')))],
        ),
      );
      return;
    }
    final flagged = <String>[
      for (var i = 0; i < _rows.length; i++)
        if (_rows[i].localWarnings().isNotEmpty) '${i + 1}. ${_rows[i].displayName}: ${_rows[i].localWarnings().join('; ')}',
    ];
    final t = _totals();
    if (_printedTotal != null && (t.total - _printedTotal!).abs() > math.max(5, _printedTotal! * 0.002)) {
      flagged.add(tr('Tổng phiếu ${_money(t.total)} đ khác tổng hóa đơn ${_money(_printedTotal!)} đ'));
    }
    if (flagged.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Kiểm tra trước khi tạo phiếu')),
          content: SizedBox(width: 460, child: SingleChildScrollView(child: Text(flagged.map((s) => '• $s').join('\n')))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Sửa lại'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn tạo'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    final body = <String, dynamic>{
      'supplierId': _createSupplier ? null : _supplierId,
      'createSupplier': _createSupplier && _supName.text.trim().isNotEmpty,
      'supplierName': _supName.text.trim().isEmpty ? null : _supName.text.trim(),
      'supplierPhone': _supPhone.text.trim().isEmpty ? null : _supPhone.text.trim(),
      'supplierTaxCode': _supTax.text.trim().isEmpty ? null : _supTax.text.trim(),
      'supplierAddress': _supAddress,
      'invoiceNo': _invoiceNo.text.trim().isEmpty ? null : _invoiceNo.text.trim(),
      'invoiceDate': _invoiceDate == null ? null : DateFormat('yyyy-MM-dd').format(_invoiceDate!),
      'discountAmount': parseMenuPrice(_invoiceDiscount.text),
      'complete': _complete,
      'paidAmount': _complete ? parseMenuPrice(_paid.text) : 0,
      'paymentMethod': _paymentMethod,
      'note': null,
      'lines': [
        for (final r in _rows) {...r.toJson(), 'vatIncluded': _pricesIncludeVat && !r.vatExempt && r.vatV > 0},
      ],
    };
    setState(() => _saving = true);
    final res = await _api.confirm(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không tạo được phiếu nhập'),
        message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
      );
      return;
    }
    final d = Map<String, dynamic>.from(res['data'] as Map? ?? const {});
    final result = PosAiInvoiceResult(
      receiptId: (d['receiptId'] ?? '').toString(),
      receiptNo: (d['receiptNo'] ?? '').toString(),
      status: (d['status'] ?? 'Draft').toString(),
    );
    final notes = ((d['warnings'] as List?) ?? const []).map((e) => '$e').toList();
    if (notes.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Đã tạo phiếu ${result.receiptNo}')),
          content: SizedBox(width: 460, child: SingleChildScrollView(child: Text(notes.map((s) => '• $s').join('\n')))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu')))],
        ),
      );
      if (!mounted) return;
    }
    Navigator.of(context).pop(result);
  }

  // ─────────────────────────── Chọn hàng / NCC ───────────────────────────

  Future<void> _pickProduct(_InvRow r) async {
    final picked = await showModalBottomSheet<_ProductRef>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductPickerSheet(api: _api, row: r),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectProduct(r, picked));
  }

  void _selectProduct(_InvRow r, _ProductRef p) {
    r.productId = p.id;
    r.productName = p.name;
    r.baseUnit = p.baseUnit;
    r.matchedBy = 'manual';
    r.createNew = false;
    // Máy chủ kiểm ĐVT quy đổi khi tạo phiếu; ĐVT khác ĐVT gốc → hỏi hệ số (bỏ trống nếu hàng đã khai báo ĐVT đó).
    final key = _unitKey(r.unit.text);
    final declared = p.units[key];
    if (declared != null) {
      r.unitStatus = 'unit';
      r.unitInfoFactor = declared.rate;
      r.unit.text = declared.name;
    } else {
      r.unitStatus = key.isEmpty || key == _unitKey(p.baseUnit) ? 'base' : 'check';
      r.unitInfoFactor = 1;
    }
    r.serverNotes = r.serverNotes
        .where((n) => !n.startsWith('Chưa') && !n.startsWith('Khớp gần đúng') && !n.startsWith('Hàng «'))
        .toList();
  }

  Future<void> _pickSupplier() async {
    if (_suppliers.isEmpty) await _loadSuppliers();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SupplierPickerSheet(suppliers: _suppliers, invoiceName: _supName.text.trim()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked['_create'] == true) {
        _createSupplier = true;
        _supplierId = null;
        _supplierName = null;
      } else if (picked['_none'] == true) {
        _createSupplier = false;
        _supplierId = null;
        _supplierName = null;
      } else {
        _createSupplier = false;
        _supplierId = picked['id']?.toString();
        _supplierName = picked['name']?.toString();
        _matchedBy = 'manual';
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _invoiceDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() => _invoiceDate = d);
  }

  void _removeRow(_InvRow r) {
    setState(() => _rows.remove(r));
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  // ─────────────────────────── Giao diện ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Chụp hóa đơn nhà cung cấp')),
        actions: [
          if (_scanned && _images.isNotEmpty)
            TextButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Đọc lại')),
            ),
        ],
      ),
      body: _scanning
          ? _buildScanning()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _buildImages(),
                if (_scanError != null) _notice(_scanError!, error: true),
                if (_scanned) ...[
                  if (_scanNotes.isNotEmpty) _notice(_scanNotes.join('\n')),
                  _buildSupplierCard(),
                  _buildInvoiceCard(),
                  _buildLinesHeader(),
                  for (var i = 0; i < _rows.length; i++) _buildRow(i, _rows[i]),
                  _buildTotalsCard(),
                  _buildCompleteCard(),
                ],
              ],
            ),
      bottomNavigationBar: _scanned && !_scanning ? _buildBottomBar() : null,
    );
  }

  Widget _buildScanning() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr('AI đang đọc hóa đơn…'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                tr('Có thể mất đến 1–2 phút, đừng tắt màn hình.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SboxColors.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SboxColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SboxColors.border),
        ),
        child: child,
      );

  Widget _notice(String text, {bool error = false}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: error ? SboxColors.dangerSoft : SboxColors.warningSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(error ? Icons.error_outline : Icons.info_outline,
                size: 18, color: error ? SboxColors.dangerText : SboxColors.warningText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, color: error ? SboxColors.dangerText : SboxColors.warningText)),
            ),
          ],
        ),
      );

  Widget _buildImages() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_scanned) ...[
            Text(tr('Ảnh hóa đơn (${_images.length}/$_maxImages)'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              tr('Chụp thẳng, đủ sáng, lấy hết bảng hàng và dòng tổng cộng. Hóa đơn nhiều trang: mỗi trang một ảnh.'),
              style: const TextStyle(fontSize: 13, color: SboxColors.textMuted),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final img in _images) _thumb(img),
              if (_images.length < _maxImages)
                InkWell(
                  onTap: _busy ? null : _addImages,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: _scanned ? 56 : 92,
                    height: _scanned ? 56 : 92,
                    decoration: BoxDecoration(
                      color: SboxColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SboxColors.borderStrong),
                    ),
                    child: _preparing
                        ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Icon(Icons.add_a_photo_outlined, color: SboxColors.textMuted),
                  ),
                ),
            ],
          ),
          if (!_scanned) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _images.isEmpty || _busy ? null : _scan,
              icon: const Icon(Icons.auto_awesome),
              label: Text(tr('Đọc hóa đơn bằng AI')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumb(_InvImage img) {
    final size = _scanned ? 56.0 : 92.0;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: img.heic
              ? Container(
                  width: size,
                  height: size,
                  color: SboxColors.slate100,
                  alignment: Alignment.center,
                  child: const Text('HEIC', style: TextStyle(fontSize: 11)),
                )
              : Image.memory(img.bytes, width: size, height: size, fit: BoxFit.cover, cacheWidth: 300),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: _busy ? null : () => setState(() => _images.remove(img)),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierCard() {
    final printed = [
      if (_supName.text.trim().isNotEmpty) _supName.text.trim(),
      if (_supTax.text.trim().isNotEmpty) '${tr('MST')} ${_supTax.text.trim()}',
      if (_supPhone.text.trim().isNotEmpty) '${tr('ĐT')} ${_supPhone.text.trim()}',
    ].join(' · ');
    final byText = switch (_matchedBy) {
      'taxCode' => tr('khớp theo mã số thuế'),
      'phone' => tr('khớp theo số điện thoại'),
      'name' => tr('khớp theo tên'),
      'fuzzy' => tr('khớp gần đúng theo tên — kiểm tra lại'),
      _ => null,
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 20, color: SboxColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Nhà cung cấp'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              TextButton(onPressed: _busy ? null : _pickSupplier, child: Text(tr('Đổi'))),
            ],
          ),
          if (printed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${tr('Trên hóa đơn')}: $printed',
                  style: const TextStyle(fontSize: 13, color: SboxColors.textMuted)),
            ),
          if (_supplierId != null)
            _statusLine(Icons.check_circle, SboxColors.successText,
                '${_supplierName ?? ''}${byText == null ? '' : ' ($byText)'}')
          else if (_createSupplier) ...[
            _statusLine(Icons.add_circle_outline, SboxColors.infoText, tr('Tạo NCC mới khi tạo phiếu')),
            const SizedBox(height: 8),
            _field(_supName, tr('Tên NCC')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_supPhone, tr('Điện thoại'), keyboard: TextInputType.phone)),
                const SizedBox(width: 8),
                Expanded(child: _field(_supTax, tr('Mã số thuế'), keyboard: TextInputType.number)),
              ],
            ),
          ] else
            _statusLine(Icons.remove_circle_outline, SboxColors.textMuted,
                tr('Không gắn NCC (phiếu không ghi công nợ NCC)')),
        ],
      ),
    );
  }

  Widget _statusLine(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      );

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard, String? suffix, ValueChanged<String>? onChanged, String? hint}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _buildInvoiceCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _field(_invoiceNo, tr('Số hóa đơn'))),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr('Ngày hóa đơn'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.event, size: 18),
                    ),
                    child: Text(_invoiceDate == null ? '—' : DateFormat('dd/MM/yyyy').format(_invoiceDate!)),
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _pricesIncludeVat,
            onChanged: (v) => setState(() => _pricesIncludeVat = v),
            title: Text(tr('Đơn giá đã gồm thuế GTGT')),
            subtitle: Text(tr('Bật khi hóa đơn bán lẻ / ghi «giá đã bao gồm VAT»')),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesHeader() {
    final review = _rows.where((r) => r.localWarnings().isNotEmpty || r.serverNotes.isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('${_rows.length} dòng hàng') + (review > 0 ? tr(' · $review dòng cần xem') : ''),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => setState(() => _rows.add(_InvRow.blank())),
            icon: const Icon(Icons.add),
            label: Text(tr('Thêm dòng')),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index, _InvRow r) {
    final notes = [...r.serverNotes, ...r.localWarnings()];
    final good = r.hasProduct && r.localWarnings().isEmpty;
    return _card(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 640;
        final cell = wide ? (c.maxWidth - 8 * 4 - 8) / 5 : (c.maxWidth - 8 - 8) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: good ? SboxColors.successSoft : SboxColors.warningSoft,
                  child: Text('${index + 1}',
                      style: TextStyle(fontSize: 11, color: good ? SboxColors.successText : SboxColors.warningText)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: tr('Xóa dòng'),
                  icon: const Icon(Icons.delete_outline, color: SboxColors.danger),
                  onPressed: _busy ? null : () => _removeRow(r),
                ),
              ],
            ),
            _buildProductPick(r),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                      width: cell,
                      child: _field(r.qty, tr('Số lượng'),
                          keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
                  SizedBox(
                      width: cell,
                      child: _field(r.unit, tr('ĐVT'), onChanged: (_) {
                        setState(() {
                          if (r.productId != null && r.unitStatus != 'unknown') {
                            r.unitStatus = _unitKey(r.unit.text) == _unitKey(r.baseUnit) ? 'base' : 'check';
                          }
                        });
                      })),
                  SizedBox(
                      width: cell,
                      child: _field(r.price, tr('Đơn giá'), keyboard: TextInputType.number, onChanged: (_) => setState(() {}))),
                  SizedBox(
                      width: cell,
                      child: _field(r.discount, tr('Chiết khấu'),
                          keyboard: TextInputType.number, onChanged: (_) => setState(() {}))),
                  SizedBox(width: cell, child: _vatPicker(r)),
                ],
              ),
            ),
            if (r.needsFactor) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('1 ${r.unit.text.trim()} = ? ${r.baseUnit ?? ''}'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: _field(r.factor, tr('Hệ số'),
                          keyboard: const TextInputType.numberWithOptions(decimal: true),
                          suffix: r.baseUnit,
                          hint: r.unitStatus == 'check' ? tr('Bỏ trống nếu đã khai báo') : null,
                          onChanged: (_) => setState(() {})),
                    ),
                  ],
                ),
              ),
              if (r.factorV > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr('→ nhập kho ${_qty(r.qtyV * r.factorV)} ${r.baseUnit ?? ''}'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.infoText),
                  ),
                ),
            ] else if (r.unitStatus == 'unit' && r.unitInfoFactor != 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('1 ${r.unit.text.trim()} = ${_qty(r.unitInfoFactor)} ${r.baseUnit ?? ''} → nhập kho ${_qty(r.qtyV * r.unitInfoFactor)} ${r.baseUnit ?? ''}'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.infoText),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.printedTotal > 0 ? '${tr('Hóa đơn')}: ${_money(r.printedTotal)} đ' : '',
                      style: const TextStyle(fontSize: 12, color: SboxColors.textMuted),
                    ),
                  ),
                  Text('${tr('Thành tiền')}: ${_money(r.gross)} đ', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• ${tr(n)}', style: const TextStyle(fontSize: 12, color: SboxColors.warningText)),
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildProductPick(_InvRow r) {
    final byText = switch (r.matchedBy) {
      'remembered' => tr('đã nhớ từ lần trước'),
      'name' => tr('trùng tên'),
      'barcode' => tr('trùng mã vạch'),
      'code' => tr('trùng mã hàng'),
      'fold' => tr('trùng tên (khác dấu)'),
      'fuzzy' => tr('gần đúng'),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!r.createNew)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: r.productId == null ? SboxColors.warningText : SboxColors.text,
                side: BorderSide(color: r.productId == null ? SboxColors.warning : SboxColors.border),
              ),
              onPressed: _busy ? null : () => _pickProduct(r),
              icon: Icon(r.productId == null ? Icons.search : Icons.inventory_2_outlined, size: 18),
              label: Text(
                r.productId == null
                    ? tr('Chọn hàng trong kho')
                    : '${r.productName ?? ''}${byText == null ? '' : ' · $byText'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (r.productId == null && !r.createNew && r.possible.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in r.possible)
                    ActionChip(
                      avatar: const Icon(Icons.lightbulb_outline, size: 16),
                      label: Text(p.name, overflow: TextOverflow.ellipsis),
                      onPressed: () => setState(() => _selectProduct(r, p)),
                    ),
                ],
              ),
            ),
          if (r.productId == null || r.createNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: r.createNew,
              onChanged: (v) => setState(() {
                r.createNew = v;
                if (v && r.newName.text.trim().isEmpty) r.newName.text = r.invoiceName;
              }),
              title: Text(tr('Tạo hàng mới')),
              subtitle: Text(tr('Giá vốn = đơn giá nhập, giá bán đặt sau trong Hàng hóa')),
            ),
          if (r.createNew) _field(r.newName, tr('Tên hàng mới')),
        ],
      ),
    );
  }

  Widget _vatPicker(_InvRow r) {
    final values = <double>{..._vatChoices, if (!r.vatExempt) r.vatRate}.toList()..sort();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: tr('Thuế GTGT'),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          isDense: true,
          isExpanded: true,
          value: r.vatExempt ? -1 : r.vatRate,
          items: [
            for (final v in values) DropdownMenuItem(value: v, child: Text('${_qty(v)}%')),
            DropdownMenuItem(value: -1, child: Text(tr('KCT'))),
          ],
          onChanged: (v) => setState(() {
            if (v == null) return;
            r.vatExempt = v < 0;
            r.vatRate = v < 0 ? 0 : v;
          }),
        ),
      ),
    );
  }

  Widget _buildTotalsCard() {
    final t = _totals();
    Widget line(String label, double v, {double? printed, bool bold = false}) {
      final off = printed != null && (v - printed).abs() > math.max(5, printed * 0.002);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
            if (printed != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '${tr('HĐ')} ${_money(printed)}',
                  style: TextStyle(fontSize: 12, color: off ? SboxColors.dangerText : SboxColors.successText),
                ),
              ),
            Text('${_money(v)} đ', style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Đối chiếu tổng'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          line(_pricesIncludeVat ? tr('Tiền hàng (trước thuế)') : tr('Cộng tiền hàng'), t.net,
              printed: _pricesIncludeVat ? null : _printedSubtotal),
          line(tr('Thuế GTGT'), t.vat, printed: _printedVat),
          const SizedBox(height: 6),
          _field(_invoiceDiscount, tr('Chiết khấu cả hóa đơn'),
              keyboard: TextInputType.number, suffix: 'đ', onChanged: (_) => setState(() {})),
          const Divider(height: 18),
          line(tr('Tổng phiếu nhập'), t.total, printed: _printedTotal, bold: true),
        ],
      ),
    );
  }

  Widget _buildCompleteCard() {
    final total = _totals().total;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _complete,
            onChanged: (v) => setState(() => _complete = v),
            title: Text(tr('Hoàn thành luôn'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_complete
                ? tr('Cộng tồn kho và ghi công nợ NCC ngay khi tạo phiếu')
                : tr('Tạo phiếu tạm — kiểm lại trên màn phiếu nhập rồi mới nhập kho')),
          ),
          if (_complete) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _field(_paid, tr('Đã trả NCC'),
                      keyboard: TextInputType.number, suffix: 'đ', onChanged: (_) => setState(() {})),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _paid.text = _money(total)),
                  child: Text(tr('Trả đủ')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr('Hình thức thanh toán'),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  isExpanded: true,
                  value: _paymentMethod,
                  items: [
                    for (final m in const ['Tiền mặt', 'Chuyển khoản']) DropdownMenuItem(value: m, child: Text(tr(m))),
                  ],
                  onChanged: (v) => setState(() => _paymentMethod = v ?? 'Tiền mặt'),
                ),
              ),
            ),
            if (_supplierId == null && !_createSupplier && parseMenuPrice(_paid.text) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('Chưa chọn NCC — số tiền đã trả không ghi vào công nợ NCC.'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.warningText)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Còn nợ NCC: ${_money(math.max(0, total - parseMenuPrice(_paid.text)))} đ'),
                style: const TextStyle(fontSize: 13, color: SboxColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final t = _totals();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: SboxColors.surface,
          border: Border(top: BorderSide(color: SboxColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('${_rows.length} dòng'), style: const TextStyle(fontSize: 12, color: SboxColors.textMuted)),
                  Text('${_money(t.total)} đ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _busy || _rows.isEmpty ? null : _confirm,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_complete ? Icons.inventory_2_outlined : Icons.save_outlined),
              label: Text(_complete ? tr('Nhập kho luôn') : tr('Tạo phiếu tạm')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tìm hàng cho một dòng hóa đơn: gợi ý của máy chủ + tìm theo tên / mã / mã vạch.
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.api, required this.row});
  final PosAiInvoiceApi api;
  final _InvRow row;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<_ProductRef> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    final list = await widget.api.searchProducts(q);
    if (!mounted || _search.text != q) return;
    setState(() {
      _loading = false;
      _results = list.map(_ProductRef.fromJson).whereType<_ProductRef>().toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _search.text.trim().length >= 2 ? _results : widget.row.possible;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                widget.row.invoiceName.isEmpty ? tr('Chọn hàng') : '${tr('Hóa đơn ghi')}: ${widget.row.invoiceName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr('Tìm tên, mã hàng, mã vạch…'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (items.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _search.text.trim().length >= 2 ? tr('Không tìm thấy hàng') : tr('Gõ ít nhất 2 ký tự để tìm hàng'),
                  style: const TextStyle(color: SboxColors.textMuted),
                ),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = items[i];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text([p.code, if (p.baseUnit != null) '${tr('ĐVT')}: ${p.baseUnit}']
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · ')),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chọn NCC có sẵn / tạo NCC mới theo hóa đơn / không gắn NCC.
class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet({required this.suppliers, required this.invoiceName});
  final List<Map<String, dynamic>> suppliers;
  final String invoiceName;

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _unitKey(_search.text);
    final list = widget.suppliers.where((s) {
      if (q.isEmpty) return true;
      return _unitKey('${s['name']} ${s['supplierCode'] ?? ''} ${s['phone'] ?? ''} ${s['taxCode'] ?? ''}').contains(q);
    }).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr('Tìm NCC theo tên, mã, SĐT, MST…'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: SboxColors.primary),
              title: Text(widget.invoiceName.isEmpty
                  ? tr('Tạo NCC mới')
                  : tr('Tạo NCC mới «${widget.invoiceName}»')),
              onTap: () => Navigator.pop(context, <String, dynamic>{'_create': true}),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: Text(tr('Không gắn NCC')),
              onTap: () => Navigator.pop(context, <String, dynamic>{'_none': true}),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final s = list[i];
                  return ListTile(
                    title: Text((s['name'] ?? '').toString()),
                    subtitle: Text([s['supplierCode'], s['phone'], s['taxCode']]
                        .where((e) => e != null && '$e'.isNotEmpty)
                        .join(' · ')),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
