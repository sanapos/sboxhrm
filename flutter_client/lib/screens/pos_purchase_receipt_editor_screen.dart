import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_purchase.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_supplier_form_dialog.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../utils/pos_purchase_receipt_print.dart';
import '../widgets/pos/pos_barcode_keyboard_scope.dart';
import '../widgets/pos_barcode_scanner.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'pos/pos_product_editor_page.dart';

const _blue = Color(0xFF2563EB);

enum _PurchaseLineColumn {
  stt('STT'),
  code('Mã hàng'),
  name('Tên hàng'),
  unit('ĐVT'),
  qty('Số lượng'),
  cost('Đơn giá'),
  discount('Giảm giá'),
  vat('VAT'),
  total('Thành tiền');

  const _PurchaseLineColumn(this.label);
  final String label;
}

Set<_PurchaseLineColumn> _defaultPurchaseColumns() => {
      _PurchaseLineColumn.stt,
      _PurchaseLineColumn.code,
      _PurchaseLineColumn.name,
      _PurchaseLineColumn.unit,
      _PurchaseLineColumn.qty,
      _PurchaseLineColumn.cost,
      _PurchaseLineColumn.discount,
      _PurchaseLineColumn.vat,
      _PurchaseLineColumn.total,
    };

class _EditorLine {
  final String productId;
  final String productCode;
  final String productName;
  final String baseUnitName;
  String? variantId;
  List<PosProductVariant> variants;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  final TextEditingController discountCtrl;
  final TextEditingController lineNoteCtrl;
  double vatRate;
  bool vatExempt;
  bool costIncludesVat;

  static const vatOptions = <double>[0, 5, 8, 10];

  _EditorLine({
    required this.productId,
    required this.productCode,
    required this.productName,
    this.baseUnitName = 'Cái',
    this.variantId,
    this.variants = const [],
    double qty = 1,
    double cost = 0,
    double discount = 0,
    this.vatRate = 0,
    this.vatExempt = false,
    this.costIncludesVat = false,
    String? lineNote,
  })  : qtyCtrl = TextEditingController(text: qty.toStringAsFixed(0)),
        costCtrl = TextEditingController(text: cost.toStringAsFixed(0)),
        discountCtrl = TextEditingController(text: discount.toStringAsFixed(0)),
        lineNoteCtrl = TextEditingController(text: lineNote ?? '');

  String get lineKey => '$productId:${variantId ?? 'base'}';

  PosProduct get _productStub => PosProduct(
        id: productId,
        productCode: productCode,
        name: productName,
        baseUnitName: baseUnitName,
        variantCount: variants.length,
      );

  List<PosProductUnitView> get unitViews =>
      buildPosProductUnitViews(_productStub, variants);

  String get unitName =>
      unitViews.where((v) => v.variantId == variantId).firstOrNull?.label ??
      baseUnitName;

  double get grossCost =>
      double.tryParse(costCtrl.text.replaceAll(',', '')) ?? 0;

  double get netUnitCost {
    if (vatExempt || vatRate <= 0 || !costIncludesVat) return grossCost;
    return grossCost / (1 + vatRate / 100);
  }

  double get lineSubtotal {
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0;
    final disc = double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0;
    return (qty * netUnitCost - disc).clamp(0, double.infinity);
  }

  double get lineVatAmount =>
      vatExempt || vatRate <= 0 ? 0 : lineSubtotal * vatRate / 100;

  double get lineTotal => lineSubtotal;

  Map<String, dynamic> toInputJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'qty': double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0,
        'costPrice': grossCost,
        'discountAmount': double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0,
        'vatRate': vatExempt ? 0 : vatRate,
        'vatIncluded': costIncludesVat && !vatExempt && vatRate > 0,
        'vatExempt': vatExempt,
        'unitName': unitName,
        if (lineNoteCtrl.text.trim().isNotEmpty) 'lineNote': lineNoteCtrl.text.trim(),
      };

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
    discountCtrl.dispose();
    lineNoteCtrl.dispose();
  }
}

class PosPurchaseReceiptEditorScreen extends StatefulWidget {
  const PosPurchaseReceiptEditorScreen({super.key, this.receiptId});

  final String? receiptId;

  @override
  State<PosPurchaseReceiptEditorScreen> createState() =>
      _PosPurchaseReceiptEditorScreenState();
}

class _PosPurchaseReceiptEditorScreenState
    extends State<PosPurchaseReceiptEditorScreen> {
  final _api = ApiService();
  final _receiptNoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  String _paymentMethod = 'Tiền mặt';
  bool _discountIsPercent = false;

  static const _paymentMethods = [
    'Tiền mặt',
    'Chuyển khoản',
    'Thẻ',
  ];

  bool _loading = true;
  bool _saving = false;
  String? _receiptId;
  String _receiptNo = '';
  String _status = 'Draft';
  String? _supplierId;
  DateTime _importDate = DateTime.now();
  List<PosSupplierFull> _suppliers = [];
  final List<_EditorLine> _lines = [];
  Set<_PurchaseLineColumn> _visibleColumns = _defaultPurchaseColumns();
  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _receiptId = widget.receiptId;
    _bootstrap();
  }

  @override
  void dispose() {
    _receiptNoCtrl.dispose();
    _noteCtrl.dispose();
    _invoiceCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await _loadSuppliers();
    if (_receiptId != null && _receiptId!.isNotEmpty) {
      await _loadReceipt(_receiptId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSuppliers() async {
    final res = await _api.getPosPurchaseSuppliers(pageSize: 200);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final items = (res['data'] as Map)['items'] as List? ?? [];
    setState(() {
      _suppliers = items
          .map((e) => PosSupplierFull.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _openAddSupplier() async {
    if (_readOnly) return;
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => const PosSupplierFormDialog(),
    );
    if (created == null || !mounted) return;
    await _loadSuppliers();
    if (created is Map && created['id'] != null) {
      setState(() => _supplierId = created['id'].toString());
    }
  }

  Future<void> _loadReceipt(String id) async {
    final res = await _api.getPosPurchaseReceipt(id);
    if (!mounted || res['isSuccess'] != true) return;
    final r = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ln in r.lines) {
      final displayCost = ln.vatIncluded && !ln.vatExempt && ln.vatRate > 0
          ? ln.costPrice * (1 + ln.vatRate / 100)
          : ln.costPrice;
      final line = _EditorLine(
        productId: ln.productId,
        productCode: ln.productCode,
        productName: ln.productName,
        baseUnitName: ln.unitName ?? 'Cái',
        variantId: ln.variantId,
        qty: ln.qty,
        cost: displayCost,
        discount: ln.discountAmount,
        vatRate: ln.vatRate,
        vatExempt: ln.vatExempt,
        costIncludesVat: ln.vatIncluded,
        lineNote: ln.lineNote,
      );
      await _loadVariantsForLine(line);
      _lines.add(line);
    }
    setState(() {
      _receiptId = r.id;
      _receiptNo = r.receiptNo;
      _receiptNoCtrl.text = r.receiptNo;
      _status = r.status;
      _supplierId = r.supplierId;
      _importDate = r.importDate?.toLocal() ?? DateTime.now();
      _noteCtrl.text = r.note ?? '';
      _invoiceCtrl.text = r.inputInvoiceNo ?? '';
      _discountIsPercent = r.discountIsPercent;
      _discountCtrl.text = r.discountIsPercent
          ? r.discountInput.toStringAsFixed(r.discountInput % 1 == 0 ? 0 : 1)
          : r.discountInput.toStringAsFixed(0);
      _paidCtrl.text = r.paidAmount.toStringAsFixed(0);
    });
  }

  double get _linesTotal => _lines.fold(0.0, (a, l) => a + l.lineTotal);

  double get _linesVatTotal => _lines.fold(0.0, (a, l) => a + l.lineVatAmount);

  double get _discountInput =>
      double.tryParse(_discountCtrl.text.replaceAll(',', '')) ?? 0;

  double get _computedReceiptDiscount {
    if (_discountIsPercent) {
      return (_linesTotal * _discountInput / 100).clamp(0, double.infinity);
    }
    return _discountInput.clamp(0, double.infinity);
  }

  double get _grandTotal =>
      (_linesTotal + _linesVatTotal - _computedReceiptDiscount).clamp(0, double.infinity);

  double get _paidAmount =>
      double.tryParse(_paidCtrl.text.replaceAll(',', '')) ?? 0;

  double get _balanceDue => _grandTotal - _paidAmount;

  Future<void> _loadVariantsForLine(_EditorLine line) async {
    if (line.variants.isNotEmpty) return;
    final vRes = await _api.getPosProductVariants(line.productId);
    if (vRes['isSuccess'] == true && vRes['data'] is List) {
      line.variants = (vRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _openDiscountEditor() async {
    if (_readOnly) return;
    final ctrl = TextEditingController(text: _discountCtrl.text);
    var isPercent = _discountIsPercent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Giảm giá phiếu'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isPercent ? 'Phần trăm (%)' : 'Số tiền (VNĐ)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('VNĐ')),
                    ButtonSegment(value: true, label: Text('%')),
                  ],
                  selected: {isPercent},
                  onSelectionChanged: (s) => setDlg(() => isPercent = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      _discountCtrl.text = ctrl.text.trim();
      _discountIsPercent = isPercent;
      setState(() {});
    }
    ctrl.dispose();
  }

  Widget _buildDiscountField() {
    final display = _discountCtrl.text.trim().isEmpty ? '0' : _discountCtrl.text.trim();
    final suffix = _discountIsPercent ? '%' : 'VNĐ';
    if (_readOnly) {
      return InputDecorator(
        decoration: PosTheme.inputDecoration(label: 'Giảm giá phiếu'),
        child: Text('$display $suffix'),
      );
    }
    return InkWell(
      onTap: _openDiscountEditor,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: PosTheme.inputDecoration(
          label: 'Giảm giá phiếu',
          suffix: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              suffix,
              style: const TextStyle(
                color: _blue,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
        child: Text(
          display,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Future<void> _editLineNote(_EditorLine line) async {
    final ctrl = TextEditingController(text: line.lineNoteCtrl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi chú dòng hàng'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Nhập ghi chú cho sản phẩm…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      line.lineNoteCtrl.text = ctrl.text.trim();
      setState(() {});
    }
    ctrl.dispose();
  }

  Future<void> _onPickProduct(PosPurchaseLookupPick pick,
      {bool mergeIfSame = false}) async {
    await _addLine(pick.product,
        preselectVariantId: pick.variantId, mergeIfSame: mergeIfSame);
  }

  Future<void> _onBarcodeScanned(String code) async {
    if (_readOnly) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) {
      await _onPickProduct(pick, mergeIfSame: true);
    }
  }

  Future<void> _scanBarcode() async {
    if (_readOnly) return;
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    await _onBarcodeScanned(code);
  }

  Future<void> _openNewProduct() async {
    if (_readOnly) return;
    final saved = await PosProductEditorPage.open(
      context,
      productType: PosProductType.goods,
    );
    if (saved == true && mounted) {
      ScreenRefreshNotifier.refreshPosProducts();
      ScreenRefreshNotifier.refreshPosSellProductGrid();
      NotificationOverlayManager().showSuccess(
        title: 'Đã thêm hàng hóa',
        message: 'Quét mã hoặc tìm tên để thêm vào phiếu',
      );
    }
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Tùy chọn hiển thị'),
          content: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _PurchaseLineColumn.values.map((c) {
                  return CheckboxListTile(
                    dense: true,
                    activeColor: _blue,
                    title: Text(c.label, style: const TextStyle(fontSize: 13)),
                    value: _visibleColumns.contains(c),
                    onChanged: (v) {
                      setDlg(() {
                        if (v == true) {
                          _visibleColumns.add(c);
                        } else if (_visibleColumns.length > 1) {
                          _visibleColumns.remove(c);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _visibleColumns = _defaultPurchaseColumns());
                Navigator.pop(ctx);
              },
              child: const Text('Mặc định'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: const Text('Xong'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printReceipt() async {
    final supplier = _suppliers.where((s) => s.id == _supplierId).firstOrNull;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await printPosPurchaseReceipt(
      context: context,
      receiptNo: _receiptNoCtrl.text.trim().isNotEmpty
          ? _receiptNoCtrl.text.trim()
          : _receiptNo,
      importDate: _importDate,
      branchName: auth.currentUser?.department,
      createdBy: auth.currentUser?.fullName,
      supplierName: supplier?.name,
      supplierAddress: supplier?.address,
      inputInvoiceNo: _invoiceCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      status: _status,
      paymentMethod: _paymentMethod,
      linesTotal: _linesTotal,
      totalVat: _linesVatTotal,
      discountAmount: _computedReceiptDiscount,
      discountIsPercent: _discountIsPercent,
      discountInput: _discountInput,
      paidAmount: _paidAmount,
      grandTotal: _grandTotal,
      lines: _lines
          .map((l) => PosPurchaseLine(
                productId: l.productId,
                variantId: l.variantId,
                productCode: l.productCode,
                productName: l.productName,
                unitName: l.unitName,
                qty: double.tryParse(l.qtyCtrl.text.replaceAll(',', '')) ?? 0,
                costPrice: l.netUnitCost,
                discountAmount:
                    double.tryParse(l.discountCtrl.text.replaceAll(',', '')) ?? 0,
                vatRate: l.vatExempt ? 0 : l.vatRate,
                vatAmount: l.lineVatAmount,
                vatIncluded: l.costIncludesVat && !l.vatExempt && l.vatRate > 0,
                vatExempt: l.vatExempt,
                lineTotal: l.lineTotal,
                lineNote: l.lineNoteCtrl.text.trim().isEmpty
                    ? null
                    : l.lineNoteCtrl.text.trim(),
              ))
          .toList(),
    );
  }

  void _adjustQty(_EditorLine line, double delta) {
    final cur = double.tryParse(line.qtyCtrl.text.replaceAll(',', '')) ?? 0;
    final next = (cur + delta).clamp(0.0001, double.infinity);
    line.qtyCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  Widget _qtyCell(_EditorLine l) {
    if (_readOnly) {
      return Text(l.qtyCtrl.text, style: const TextStyle(fontSize: 13));
    }
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.remove, size: 18),
          onPressed: () => _adjustQty(l, -1),
        ),
        Expanded(
          child: TextField(
            controller: l.qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.add, size: 18, color: _blue),
          onPressed: () => _adjustQty(l, 1),
        ),
      ],
    );
  }

  Widget _vatCell(_EditorLine l) {
    if (_readOnly) {
      final label = l.vatExempt
          ? 'KCT'
          : l.vatRate <= 0
              ? '—'
              : '${l.vatRate.toStringAsFixed(0)}%';
      return Text(label, style: const TextStyle(fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: l.vatExempt ? 'kct' : l.vatRate.toStringAsFixed(0),
            isDense: true,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 'kct', child: Text('KCT')),
              ..._EditorLine.vatOptions.map(
                (r) => DropdownMenuItem(
                  value: r.toStringAsFixed(0),
                  child: Text(r <= 0 ? '0%' : '${r.toStringAsFixed(0)}%'),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() {
                if (v == 'kct') {
                  l.vatExempt = true;
                  l.vatRate = 0;
                  l.costIncludesVat = false;
                } else {
                  l.vatExempt = false;
                  l.vatRate = double.tryParse(v ?? '0') ?? 0;
                }
              });
            },
          ),
        ),
        if (!l.vatExempt && l.vatRate > 0)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: const Text('Đã bao gồm thuế', style: TextStyle(fontSize: 11)),
            value: l.costIncludesVat,
            activeColor: _blue,
            onChanged: (v) => setState(() => l.costIncludesVat = v == true),
          ),
      ],
    );
  }

  Future<void> _addLine(PosProduct p,
      {String? preselectVariantId, bool mergeIfSame = false}) async {
    List<PosProductVariant> variants = [];
    if (p.variantCount > 0) {
      final vRes = await _api.getPosProductVariants(p.id);
      if (vRes['isSuccess'] == true && vRes['data'] is List) {
        variants = (vRes['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    final line = _EditorLine(
      productId: p.id,
      productCode: p.productCode,
      productName: p.name,
      baseUnitName: p.baseUnitName,
      variantId: preselectVariantId ??
          (variants.isNotEmpty ? resolveUnitView(p, variants, null).variantId : null),
      variants: variants,
      cost: p.costPrice,
    );
    if (preselectVariantId != null && variants.isNotEmpty) {
      final v = variants.where((x) => x.id == preselectVariantId).firstOrNull;
      if (v != null) {
        line.costCtrl.text = v.costPrice.toStringAsFixed(0);
      }
    }
    if (_lines.any((l) => l.lineKey == line.lineKey)) {
      if (mergeIfSame) {
        final existing = _lines.firstWhere((l) => l.lineKey == line.lineKey);
        line.dispose();
        final cur = double.tryParse(existing.qtyCtrl.text.replaceAll(',', '')) ?? 0;
        existing.qtyCtrl.text = (cur + 1).toStringAsFixed(0);
        setState(() {});
        return;
      }
      line.dispose();
      NotificationOverlayManager()
          .showWarning(title: 'Trùng', message: 'Hàng đã có trong phiếu');
      return;
    }
    await _loadVariantsForLine(line);
    setState(() => _lines.add(line));
  }

  Map<String, dynamic> _buildBody({required bool complete}) {
    final manualNo = _receiptNoCtrl.text.trim();
    return {
        'supplierId': _supplierId,
        'note': _noteCtrl.text.trim(),
        'inputInvoiceNo': _invoiceCtrl.text.trim(),
        if (manualNo.isNotEmpty) 'receiptNo': manualNo,
        'discountAmount': _computedReceiptDiscount,
        'discountIsPercent': _discountIsPercent,
        'discountInput': _discountInput,
        'paidAmount': _paidAmount,
        'paymentMethod': _paymentMethod,
        'importDate': _importDate.toUtc().toIso8601String(),
        'complete': complete,
        'lines': _lines.map((l) => l.toInputJson()).toList(),
      };
  }

  Future<void> _save({required bool complete}) async {
    if (_lines.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'Phiếu trống', message: 'Thêm ít nhất một dòng hàng');
      return;
    }
    setState(() => _saving = true);
    final body = _buildBody(complete: complete);
    Map<String, dynamic> res;
    if (_receiptId != null && _receiptId!.isNotEmpty) {
      res = await _api.updatePosPurchaseReceipt(_receiptId!, body);
    } else {
      res = await _api.createPosPurchaseReceipt(body);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      final r = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager().showSuccess(
        title: complete ? 'Đã nhập hàng' : 'Đã lưu phiếu tạm',
        message: r.receiptNo,
      );
      if (complete && mounted) Navigator.pop(context, true);
      else await _loadReceipt(r.id);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _completeExisting() async {
    if (_receiptId == null) return;
    setState(() => _saving = true);
    final res = await _api.completePosPurchaseReceipt(_receiptId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Hoàn tất', message: 'Phiếu đã nhập hàng');
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _deleteDraft() async {
    if (_receiptId == null || _receiptId!.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text('Xóa hẳn phiếu $_receiptNo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosPurchaseReceipt(_receiptId!);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: _receiptNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
    }
  }

  Future<void> _voidCompleted() async {
    if (_receiptId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu nhập'),
        content: Text('Hủy phiếu $_receiptNo và trừ lại hàng đã nhập kho?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy phiếu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await _api.cancelPosPurchaseReceipt(_receiptId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy', message: 'Đã hoàn kho · $_receiptNo');
      await _loadReceipt(_receiptId!);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canEdit('PosProducts')) {
      return const Scaffold(body: Center(child: Text('Không có quyền nhập hàng')));
    }

    return PosBarcodeKeyboardScope(
      enabled: !_readOnly && !_loading,
      onBarcode: _onBarcodeScanned,
      child: Scaffold(
            backgroundColor: HrmPageChrome.background,
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: PosTheme.textPrimary,
              elevation: 0,
              title: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, color: _blue, size: 22),
                  const SizedBox(width: 8),
                  Text(_receiptId == null ? 'Nhập hàng' : 'Nhập hàng · $_receiptNo'),
                ],
              ),
            ),
            body: _loading
                ? const LoadingWidget()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Row(
                                children: [
                                  if (!_readOnly)
                                    Expanded(
                                      child: PosPurchaseProductSearchBar(
                                        api: _api,
                                        readOnly: _readOnly,
                                        onPick: (pick) => _onPickProduct(pick),
                                        onBarcodePick: (pick) =>
                                            _onPickProduct(pick, mergeIfSame: true),
                                        onAddProduct: _openNewProduct,
                                      ),
                                    )
                                  else
                                    const Expanded(
                                      child: Text('Chi tiết phiếu nhập hàng',
                                          style: TextStyle(
                                              fontSize: 15, fontWeight: FontWeight.w600)),
                                    ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Quét mã vạch',
                                    icon: const Icon(Icons.qr_code_scanner_outlined),
                                    onPressed: _readOnly ? null : _scanBarcode,
                                  ),
                                  IconButton(
                                    tooltip: 'Tùy chọn hiển thị',
                                    icon: const Icon(Icons.visibility_outlined),
                                    onPressed: _showColumnPicker,
                                  ),
                                  IconButton(
                                    tooltip: 'Lệnh in',
                                    icon: const Icon(Icons.print_outlined),
                                    onPressed: _lines.isEmpty ? null : _printReceipt,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _lines.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inventory_2_outlined,
                                              size: 48, color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          Text('Chưa có hàng trong phiếu',
                                              style: TextStyle(color: Colors.grey.shade600)),
                                          const SizedBox(height: 8),
                                          Text('Tìm theo mã, tên hoặc quét mã vạch (F3)',
                                              style: TextStyle(
                                                  fontSize: 12, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    )
                                  : ColoredBox(
                                      color: Colors.white,
                                      child: _buildFullWidthLinesTable(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 320,
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Ngày nhập', style: TextStyle(fontSize: 12)),
                                subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(_importDate)),
                                trailing: _readOnly
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.calendar_today, size: 18),
                                        onPressed: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate: _importDate,
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime(2100),
                                          );
                                          if (d != null) setState(() => _importDate = d);
                                        },
                                      ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _supplierId,
                                      decoration: PosTheme.inputDecoration(label: 'Nhà cung cấp'),
                                      items: [
                                        const DropdownMenuItem(
                                            value: null, child: Text('— Chọn NCC —')),
                                        ..._suppliers.map((s) => DropdownMenuItem(
                                              value: s.id,
                                              child: Text('${s.supplierCode} · ${s.name}',
                                                  overflow: TextOverflow.ellipsis),
                                            )),
                                      ],
                                      onChanged:
                                          _readOnly ? null : (v) => setState(() => _supplierId = v),
                                    ),
                                  ),
                                  if (!_readOnly) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Thêm NCC',
                                      onPressed: _openAddSupplier,
                                      icon: const Icon(Icons.add_business, color: _blue),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _receiptNoCtrl,
                                readOnly: _readOnly,
                                decoration: PosTheme.inputDecoration(
                                  label: 'Mã phiếu nhập',
                                  hint: 'Tự sinh khi lưu',
                                ),
                                onChanged: (v) => setState(() => _receiptNo = v.trim()),
                              ),
                              const SizedBox(height: 12),
                              InputDecorator(
                                decoration: PosTheme.inputDecoration(label: 'Trạng thái'),
                                child: purchaseStatusChip(_status),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _invoiceCtrl,
                                readOnly: _readOnly,
                                decoration: PosTheme.inputDecoration(label: 'Hóa đơn đầu vào'),
                              ),
                              const SizedBox(height: 12),
                              _buildDiscountField(),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _paidCtrl,
                                readOnly: _readOnly,
                                keyboardType: TextInputType.number,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Tiền trả nhà cung cấp'),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _paymentMethod,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Phương thức thanh toán'),
                                items: _paymentMethods
                                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                    .toList(),
                                onChanged: _readOnly
                                    ? null
                                    : (v) => setState(
                                        () => _paymentMethod = v ?? 'Tiền mặt'),
                              ),
                              const Divider(height: 24),
                              _totalRow('Tổng tiền hàng', _moneyFmt.format(_linesTotal)),
                              _totalRow('Tổng VAT', _moneyFmt.format(_linesVatTotal)),
                              _totalRow(
                                'Giảm giá',
                                _discountIsPercent
                                    ? '${_discountInput.toStringAsFixed(_discountInput % 1 == 0 ? 0 : 1)}% (${_moneyFmt.format(_computedReceiptDiscount)})'
                                    : _moneyFmt.format(_computedReceiptDiscount),
                              ),
                              _totalRow('Cần trả nhà cung cấp', _moneyFmt.format(_grandTotal),
                                  bold: true, color: _blue),
                              _totalRow('Tính vào công nợ', _moneyFmt.format(_balanceDue),
                                  bold: true,
                                  color: _balanceDue > 0 ? Colors.orange.shade800 : null),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _noteCtrl,
                                readOnly: _readOnly,
                                maxLines: 3,
                                decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                              ),
                              if (!_readOnly && perm.canEdit('PosProducts')) ...[
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: _saving ? null : () => _save(complete: false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _blue,
                                    side: const BorderSide(color: _blue),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: Text(_saving ? 'Đang lưu…' : 'Lưu tạm'),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: _saving ? null : () => _save(complete: true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _blue,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: Text(_saving ? 'Đang lưu…' : 'Hoàn thành'),
                                ),
                                if (_receiptId != null) ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: _saving ? null : _deleteDraft,
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    label: const Text('Xóa phiếu'),
                                  ),
                                ],
                              ] else if (_status == 'Completed' &&
                                  _receiptId != null &&
                                  perm.canEdit('PosProducts')) ...[
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _voidCompleted,
                                  icon: const Icon(Icons.cancel_outlined, size: 18),
                                  label: const Text('Hủy phiếu'),
                                ),
                              ] else if (_status == 'Cancelled' &&
                                  _receiptId != null &&
                                  perm.canEdit('PosProducts')) ...[
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _deleteDraft,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Xóa phiếu'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
    ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: color,
                  fontSize: bold ? 16 : 13)),
        ],
      ),
    );
  }

  int _colFlex(_PurchaseLineColumn c) => switch (c) {
        _PurchaseLineColumn.stt => 1,
        _PurchaseLineColumn.code => 2,
        _PurchaseLineColumn.name => 5,
        _PurchaseLineColumn.unit => 2,
        _PurchaseLineColumn.qty => 2,
        _PurchaseLineColumn.cost => 2,
        _PurchaseLineColumn.discount => 2,
        _PurchaseLineColumn.vat => 2,
        _PurchaseLineColumn.total => 2,
      };

  Widget _unitCell(_EditorLine l) {
    final views = l.unitViews;
    if (_readOnly || views.length <= 1) {
      return Text(l.unitName, style: const TextStyle(fontSize: 13));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: l.variantId,
        isDense: true,
        isExpanded: true,
        items: views
            .map((v) => DropdownMenuItem<String?>(
                  value: v.variantId,
                  child: Text(v.label, style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        onChanged: (vid) {
          setState(() {
            l.variantId = vid;
            final view = views.where((x) => x.variantId == vid).firstOrNull;
            if (view != null) {
              l.costCtrl.text = view.costPrice.toStringAsFixed(0);
            }
          });
        },
      ),
    );
  }

  Widget _buildFullWidthLinesTable() {
    final cols = _PurchaseLineColumn.values
        .where((c) => _visibleColumns.contains(c))
        .toList();

    Widget headerCell(String label, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        );

    Widget dataCell(Widget child, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: child,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...cols.map((c) => headerCell(c.label, _colFlex(c))),
                if (!_readOnly)
                  const SizedBox(
                    width: 40,
                    child: Center(child: SizedBox.shrink()),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _lines.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) {
              final l = _lines[i];
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ...cols.map((c) {
                      final flex = _colFlex(c);
                      switch (c) {
                        case _PurchaseLineColumn.stt:
                          return dataCell(
                              Text('${i + 1}', style: const TextStyle(fontSize: 13)), flex);
                        case _PurchaseLineColumn.code:
                          return dataCell(
                              Text(l.productCode, style: const TextStyle(fontSize: 13)), flex);
                        case _PurchaseLineColumn.name:
                          return dataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(l.productName,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w500)),
                                if (!_readOnly)
                                  InkWell(
                                    onTap: () => _editLineNote(l),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit_outlined,
                                              size: 12, color: Colors.grey.shade600),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              l.lineNoteCtrl.text.isEmpty
                                                  ? 'Ghi chú…'
                                                  : l.lineNoteCtrl.text,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: l.lineNoteCtrl.text.isEmpty
                                                    ? Colors.grey.shade500
                                                    : Colors.grey.shade700,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else if (l.lineNoteCtrl.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      l.lineNoteCtrl.text,
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey.shade600),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                            flex,
                          );
                        case _PurchaseLineColumn.unit:
                          return dataCell(_unitCell(l), flex);
                        case _PurchaseLineColumn.qty:
                          return dataCell(_qtyCell(l), flex);
                        case _PurchaseLineColumn.cost:
                          return dataCell(
                            TextField(
                              controller: l.costCtrl,
                              readOnly: _readOnly,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            flex,
                          );
                        case _PurchaseLineColumn.discount:
                          return dataCell(
                            TextField(
                              controller: l.discountCtrl,
                              readOnly: _readOnly,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            flex,
                          );
                        case _PurchaseLineColumn.vat:
                          return dataCell(_vatCell(l), flex);
                        case _PurchaseLineColumn.total:
                          return dataCell(
                            Text(_moneyFmt.format(l.lineTotal),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            flex,
                          );
                      }
                    }),
                    if (!_readOnly)
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() {
                              l.dispose();
                              _lines.removeAt(i);
                            });
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
