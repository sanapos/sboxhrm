import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_purchase.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_supplier_form_dialog.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos_barcode_scanner.dart';

const _blue = Color(0xFF2563EB);

class _ReturnLine {
  final String productId;
  final String productCode;
  final String productName;
  final String baseUnitName;
  final double importCost;
  String? variantId;
  List<PosProductVariant> variants;
  final TextEditingController qtyCtrl;
  final TextEditingController returnPriceCtrl;
  final TextEditingController discountCtrl;
  final TextEditingController lineNoteCtrl;

  _ReturnLine({
    required this.productId,
    required this.productCode,
    required this.productName,
    this.baseUnitName = 'Cái',
    this.importCost = 0,
    this.variantId,
    this.variants = const [],
    double qty = 1,
    double returnPrice = 0,
    double discount = 0,
    String? lineNote,
  })  : qtyCtrl = TextEditingController(text: qty.toStringAsFixed(0)),
        returnPriceCtrl = TextEditingController(text: returnPrice.toStringAsFixed(0)),
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

  double get lineTotal {
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0;
    final price = double.tryParse(returnPriceCtrl.text.replaceAll(',', '')) ?? 0;
    final disc = double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0;
    return (qty * price - disc).clamp(0, double.infinity);
  }

  Map<String, dynamic> toInputJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'qty': double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0,
        'costPrice': double.tryParse(returnPriceCtrl.text.replaceAll(',', '')) ?? 0,
        'discountAmount': double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0,
        'unitName': unitName,
        if (lineNoteCtrl.text.trim().isNotEmpty) 'lineNote': lineNoteCtrl.text.trim(),
      };

  void dispose() {
    qtyCtrl.dispose();
    returnPriceCtrl.dispose();
    discountCtrl.dispose();
    lineNoteCtrl.dispose();
  }
}

class PosPurchaseReturnEditorScreen extends StatefulWidget {
  const PosPurchaseReturnEditorScreen({
    super.key,
    this.returnId,
    this.sourceReceiptId,
  });

  final String? returnId;
  final String? sourceReceiptId;

  @override
  State<PosPurchaseReturnEditorScreen> createState() =>
      _PosPurchaseReturnEditorScreenState();
}

class _PosPurchaseReturnEditorScreenState
    extends State<PosPurchaseReturnEditorScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _refundReceivedCtrl = TextEditingController(text: '0');
  final _returnNoCtrl = TextEditingController();
  final _receiptSearchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  String _paymentMethod = 'Tiền mặt';

  bool _loading = true;
  bool _saving = false;
  String? _returnId;
  String _returnNo = '';
  String _status = 'Draft';
  String? _supplierId;
  String? _sourceReceiptId;
  String? _sourceReceiptNo;
  String? _returnedBy;
  DateTime _returnDate = DateTime.now();
  List<PosSupplierFull> _suppliers = [];
  final List<_ReturnLine> _lines = [];

  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _returnId = widget.returnId;
    _sourceReceiptId = widget.sourceReceiptId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _discountCtrl.dispose();
    _refundReceivedCtrl.dispose();
    _returnNoCtrl.dispose();
    _receiptSearchCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _returnedBy ??= auth.currentUser?.fullName ?? auth.currentUser?.email;
    await _loadSuppliers();
    if (_returnId != null && _returnId!.isNotEmpty) {
      await _loadReturn(_returnId!);
    } else if (_sourceReceiptId != null && _sourceReceiptId!.isNotEmpty) {
      await _loadFromReceipt(_sourceReceiptId!);
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

  Future<void> _loadVariantsForLine(_ReturnLine line) async {
    if (line.variants.isNotEmpty) return;
    final vRes = await _api.getPosProductVariants(line.productId);
    if (vRes['isSuccess'] == true && vRes['data'] is List) {
      line.variants = (vRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  void _applyReturn(PosPurchaseReturn r) {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ln in r.lines) {
      final line = _ReturnLine(
        productId: ln.productId,
        productCode: ln.productCode,
        productName: ln.productName,
        baseUnitName: ln.unitName ?? 'Cái',
        importCost: ln.costPrice,
        variantId: ln.variantId,
        qty: ln.qty,
        returnPrice: ln.costPrice,
        discount: ln.discountAmount,
        lineNote: ln.lineNote,
      );
      _loadVariantsForLine(line);
      _lines.add(line);
    }
    _returnId = r.id.isEmpty ? null : r.id;
    _returnNo = r.returnNo;
    _returnNoCtrl.text = r.returnNo;
    _status = r.status;
    _supplierId = r.supplierId;
    _sourceReceiptId = r.sourceReceiptId;
    _sourceReceiptNo = r.sourceReceiptNo;
    _returnDate = r.returnDate?.toLocal() ?? DateTime.now();
    _returnedBy = r.returnedBy;
    _noteCtrl.text = r.note ?? '';
    _discountCtrl.text = r.discountAmount.toStringAsFixed(0);
    _refundReceivedCtrl.text = r.refundReceived.toStringAsFixed(0);
  }

  Future<void> _loadReturn(String id) async {
    final res = await _api.getPosPurchaseReturn(id);
    if (!mounted || res['isSuccess'] != true) return;
    setState(() => _applyReturn(
        PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>)));
  }

  Future<void> _loadFromReceipt(String receiptId) async {
    final res = await _api.getPosPurchaseReturnFromReceipt(receiptId);
    if (!mounted || res['isSuccess'] != true) return;
    setState(() => _applyReturn(
        PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>)));
  }

  Future<void> _loadFromReceiptSearch() async {
    final q = _receiptSearchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);

    String? receiptId;
    final isGuid = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(q);
    if (isGuid) {
      receiptId = q;
    } else {
      final listRes = await _api.getPosPurchaseReceipts(search: q, pageSize: 1);
      if (listRes['isSuccess'] == true && listRes['data'] is Map) {
        final items = (listRes['data'] as Map)['items'] as List? ?? [];
        if (items.isNotEmpty) {
          receiptId = (items.first as Map)['id']?.toString();
        }
      }
    }

    if (receiptId == null) {
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Không tìm thấy', message: 'Không tìm thấy phiếu nhập "$q"');
        setState(() => _loading = false);
      }
      return;
    }

    await _loadFromReceipt(receiptId);
    if (mounted) setState(() => _loading = false);
  }

  double get _linesTotal => _lines.fold(0.0, (a, l) => a + l.lineTotal);

  double get _discountAmount =>
      double.tryParse(_discountCtrl.text.replaceAll(',', '')) ?? 0;

  double get _refundReceived =>
      double.tryParse(_refundReceivedCtrl.text.replaceAll(',', '')) ?? 0;

  double get _supplierOwed => (_linesTotal - _discountAmount).clamp(0, double.infinity);

  double get _debtBalance => _supplierOwed - _refundReceived;

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    List<PosProductVariant> variants = [];
    if (pick.product.variantCount > 0) {
      final vRes = await _api.getPosProductVariants(pick.product.id);
      if (vRes['isSuccess'] == true && vRes['data'] is List) {
        variants = (vRes['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    final view = resolveUnitView(pick.product, variants, pick.variantId);
    final cost = view.costPrice > 0 ? view.costPrice : pick.product.costPrice;
    final line = _ReturnLine(
      productId: pick.product.id,
      productCode: view.displayCode,
      productName: pick.product.name,
      baseUnitName: pick.product.baseUnitName,
      importCost: cost,
      variantId: view.variantId,
      variants: variants,
      returnPrice: cost,
    );
    if (_lines.any((l) => l.lineKey == line.lineKey)) {
      line.dispose();
      NotificationOverlayManager()
          .showWarning(title: 'Trùng', message: 'Hàng đã có trong phiếu');
      return;
    }
    await _loadVariantsForLine(line);
    setState(() => _lines.add(line));
  }

  Future<void> _scanBarcode() async {
    if (_readOnly) return;
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _onPickProduct(pick);
  }

  Future<void> _editLineNote(_ReturnLine line) async {
    final ctrl = TextEditingController(text: line.lineNoteCtrl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi chú dòng hàng'),
        content: TextField(controller: ctrl, maxLines: 3),
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

  void _adjustQty(_ReturnLine line, double delta) {
    final cur = double.tryParse(line.qtyCtrl.text.replaceAll(',', '')) ?? 0;
    final next = (cur + delta).clamp(0.0001, double.infinity);
    line.qtyCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  Map<String, dynamic> _buildBody({required bool complete}) => {
        'supplierId': _supplierId,
        'sourceReceiptId': _sourceReceiptId,
        'note': _noteCtrl.text.trim(),
        'discountAmount': _discountAmount,
        'refundReceived': _refundReceived,
        'returnDate': _returnDate.toUtc().toIso8601String(),
        'returnedBy': _returnedBy,
        'complete': complete,
        'lines': _lines.map((l) => l.toInputJson()).toList(),
      };

  Future<void> _save({required bool complete}) async {
    if (_lines.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'Phiếu trống', message: 'Thêm ít nhất một dòng hàng');
      return;
    }
    setState(() => _saving = true);
    final body = _buildBody(complete: complete);
    Map<String, dynamic> res;
    if (_returnId != null && _returnId!.isNotEmpty) {
      res = await _api.updatePosPurchaseReturn(_returnId!, body);
    } else {
      res = await _api.createPosPurchaseReturn(body);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      final r = PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager().showSuccess(
        title: complete ? 'Đã trả hàng' : 'Đã lưu phiếu tạm',
        message: r.returnNo,
      );
      if (complete && mounted) {
        Navigator.pop(context, true);
      } else {
        await _loadReturn(r.id);
      }
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _completeExisting() async {
    if (_returnId == null) return;
    setState(() => _saving = true);
    final res = await _api.completePosPurchaseReturn(_returnId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Hoàn tất', message: 'Phiếu đã trả hàng');
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _deleteDraft() async {
    if (_returnId == null || _returnId!.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text('Xóa hẳn phiếu $_returnNo?'),
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
    final res = await _api.deletePosPurchaseReturn(_returnId!);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: _returnNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
    }
  }

  Future<void> _voidCompleted() async {
    if (_returnId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu trả hàng'),
        content: Text('Hủy phiếu $_returnNo và hoàn hàng về kho?'),
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
    final res = await _api.cancelPosPurchaseReturn(_returnId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy', message: 'Đã hoàn kho · $_returnNo');
      await _loadReturn(_returnId!);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  Widget _qtyCell(_ReturnLine l) {
    if (_readOnly) return Text(l.qtyCtrl.text, style: const TextStyle(fontSize: 13));
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

  Widget _unitCell(_ReturnLine l) {
    if (_readOnly || l.unitViews.length <= 1) {
      return Text(l.unitName, style: const TextStyle(fontSize: 13));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: l.variantId,
        isDense: true,
        isExpanded: true,
        items: l.unitViews
            .map((v) => DropdownMenuItem<String?>(
                  value: v.variantId,
                  child: Text(v.label, style: const TextStyle(fontSize: 12)),
                ))
            .toList(),
        onChanged: (v) {
          setState(() {
            l.variantId = v;
            final view = l.unitViews.where((x) => x.variantId == v).firstOrNull;
            if (view != null && view.costPrice > 0) {
              l.returnPriceCtrl.text = view.costPrice.toStringAsFixed(0);
            }
          });
        },
      ),
    );
  }

  Widget _buildLinesTable() {
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
              children: [
                headerCell('STT', 1),
                headerCell('Mã hàng', 2),
                headerCell('Tên hàng', 4),
                headerCell('ĐVT', 2),
                headerCell('Số lượng', 2),
                headerCell('Giá nhập', 2),
                headerCell('Giá trả lại', 2),
                headerCell('Giảm giá', 2),
                headerCell('Thành tiền', 2),
                if (!_readOnly) const SizedBox(width: 40),
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
                    dataCell(Text('${i + 1}', style: const TextStyle(fontSize: 13)), 1),
                    dataCell(
                        Text(l.productCode,
                            style: const TextStyle(fontSize: 13, color: _blue)),
                        2),
                    dataCell(
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
                        ],
                      ),
                      4,
                    ),
                    dataCell(_unitCell(l), 2),
                    dataCell(_qtyCell(l), 2),
                    dataCell(
                        Text('${_moneyFmt.format(l.importCost)} đ',
                            style: const TextStyle(fontSize: 13)),
                        2),
                    dataCell(
                      _readOnly
                          ? Text('${_moneyFmt.format(double.tryParse(l.returnPriceCtrl.text) ?? 0)} đ',
                              style: const TextStyle(fontSize: 13))
                          : TextField(
                              controller: l.returnPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                      2,
                    ),
                    dataCell(
                      _readOnly
                          ? Text(l.discountCtrl.text, style: const TextStyle(fontSize: 13))
                          : TextField(
                              controller: l.discountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                      2,
                    ),
                    dataCell(
                        Text('${_moneyFmt.format(l.lineTotal)} đ',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        2),
                    if (!_readOnly)
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
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

  Widget _totalRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: color,
                  fontSize: bold ? 15 : 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canEdit('PosProducts')) {
      return const Scaffold(body: Center(child: Text('Không có quyền trả hàng nhập')));
    }

    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.f3): _ReturnSearchIntent()},
      child: Actions(
        actions: {
          _ReturnSearchIntent: CallbackAction<_ReturnSearchIntent>(onInvoke: (_) => null),
        },
        child: Scaffold(
          backgroundColor: HrmPageChrome.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: PosTheme.textPrimary,
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.assignment_return_outlined, color: _blue, size: 22),
                const SizedBox(width: 8),
                Text(_returnId == null ? 'Trả hàng nhập' : 'Trả hàng · $_returnNo'),
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
                                if (!_readOnly && _sourceReceiptId == null)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: _receiptSearchCtrl,
                                            decoration: const InputDecoration(
                                              hintText: 'Tải từ phiếu nhập (mã PN)…',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              filled: true,
                                              fillColor: Colors.white,
                                            ),
                                            onSubmitted: (_) => _loadFromReceiptSearch(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: _loadFromReceiptSearch,
                                          child: const Text('Tải PN'),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 3,
                                          child: PosPurchaseProductSearchBar(
                                            api: _api,
                                            readOnly: _readOnly,
                                            hintText: 'Tìm hàng hóa (F3)',
                                            onPick: _onPickProduct,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (!_readOnly)
                                  Expanded(
                                    child: PosPurchaseProductSearchBar(
                                      api: _api,
                                      readOnly: _readOnly,
                                      hintText: 'Tìm hàng hóa (F3)',
                                      onPick: _onPickProduct,
                                    ),
                                  )
                                else
                                  const Expanded(
                                    child: Text('Chi tiết phiếu trả hàng nhập',
                                        style: TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.w600)),
                                  ),
                                IconButton(
                                  tooltip: 'Quét mã vạch',
                                  icon: const Icon(Icons.qr_code_scanner_outlined),
                                  onPressed: _readOnly ? null : _scanBarcode,
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
                                        Icon(Icons.assignment_return_outlined,
                                            size: 48, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text('Chưa có hàng trong phiếu trả',
                                            style: TextStyle(color: Colors.grey.shade600)),
                                        const SizedBox(height: 8),
                                        Text('Tìm hàng hoặc tải từ phiếu nhập (F3)',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.grey.shade500)),
                                      ],
                                    ),
                                  )
                                : ColoredBox(
                                    color: Colors.white,
                                    child: _buildLinesTable(),
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
                            if (_sourceReceiptNo != null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Phiếu nhập gốc',
                                    style: TextStyle(fontSize: 12)),
                                subtitle: Text(_sourceReceiptNo!,
                                    style: const TextStyle(
                                        color: _blue, fontWeight: FontWeight.w600)),
                              ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Ngày trả', style: TextStyle(fontSize: 12)),
                              subtitle:
                                  Text(DateFormat('dd/MM/yyyy HH:mm').format(_returnDate)),
                              trailing: _readOnly
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.calendar_today, size: 18),
                                      onPressed: () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate: _returnDate,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (d != null) {
                                          setState(() => _returnDate = DateTime(
                                              d.year, d.month, d.day,
                                              _returnDate.hour, _returnDate.minute));
                                        }
                                      },
                                    ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _supplierId,
                                    decoration:
                                        PosTheme.inputDecoration(label: 'Tìm nhà cung cấp'),
                                    items: [
                                      const DropdownMenuItem(
                                          value: null, child: Text('— Chọn NCC —')),
                                      ..._suppliers.map((s) => DropdownMenuItem(
                                            value: s.id,
                                            child: Text('${s.supplierCode} · ${s.name}',
                                                overflow: TextOverflow.ellipsis),
                                          )),
                                    ],
                                    onChanged: _readOnly
                                        ? null
                                        : (v) => setState(() => _supplierId = v),
                                  ),
                                ),
                                if (!_readOnly) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Thêm NCC',
                                    onPressed: _openAddSupplier,
                                    icon: const Icon(Icons.add, color: _blue),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _returnNoCtrl,
                              readOnly: true,
                              decoration: PosTheme.inputDecoration(
                                label: 'Mã trả hàng nhập',
                                hint: 'Mã phiếu tự động',
                              ),
                            ),
                            const SizedBox(height: 12),
                            InputDecorator(
                              decoration: PosTheme.inputDecoration(label: 'Trạng thái'),
                              child: purchaseStatusChip(_status, completedLabel: 'Đã trả hàng'),
                            ),
                            const Divider(height: 24),
                            _totalRow('Tổng tiền hàng (${_lines.length})',
                                '${_moneyFmt.format(_linesTotal)} đ'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _discountCtrl,
                              readOnly: _readOnly,
                              keyboardType: TextInputType.number,
                              decoration: PosTheme.inputDecoration(label: 'Giảm giá'),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _totalRow('NCC cần trả', '${_moneyFmt.format(_supplierOwed)} đ',
                                bold: true),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _refundReceivedCtrl,
                              readOnly: _readOnly,
                              keyboardType: TextInputType.number,
                              decoration: PosTheme.inputDecoration(
                                  label: 'Tiền NCC trả (F8)'),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _paymentMethod,
                              decoration: PosTheme.inputDecoration(label: 'Phương thức'),
                              items: const [
                                DropdownMenuItem(value: 'Tiền mặt', child: Text('Tiền mặt')),
                                DropdownMenuItem(
                                    value: 'Chuyển khoản', child: Text('Chuyển khoản')),
                              ],
                              onChanged:
                                  _readOnly ? null : (v) => setState(() => _paymentMethod = v!),
                            ),
                            const SizedBox(height: 8),
                            _totalRow(
                              'Tính vào công nợ',
                              '${_moneyFmt.format(_debtBalance)} đ',
                              bold: true,
                              color: _debtBalance > 0 ? _blue : null,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _noteCtrl,
                              readOnly: _readOnly,
                              maxLines: 3,
                              decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                            ),
                            if (!_readOnly) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _saving ? null : () => _save(complete: false),
                                child: Text(_saving ? '…' : 'Lưu tạm'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _saving ? null : () => _save(complete: true),
                                style: FilledButton.styleFrom(backgroundColor: _blue),
                                child: Text(_saving ? '…' : 'Hoàn thành'),
                              ),
                              if (_returnId != null) ...[
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _deleteDraft,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Xóa phiếu'),
                                ),
                              ],
                            ] else if (_status == 'Completed' && _returnId != null) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _voidCompleted,
                                icon: const Icon(Icons.cancel_outlined, size: 18),
                                label: const Text('Hủy phiếu'),
                              ),
                            ] else if (_status == 'Cancelled' && _returnId != null) ...[
                              const SizedBox(height: 16),
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
      ),
    );
  }
}

class _ReturnSearchIntent extends Intent {
  const _ReturnSearchIntent();
}
