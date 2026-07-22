import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/pos_purchase.dart';
import '../../../services/api_service.dart';
import '../../../utils/pos_purchase_product_lookup.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/notification_overlay.dart';
import '../../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../../../widgets/pos_barcode_scanner.dart';
import '../../../widgets/warehouse/wh_mobile_components.dart';
import '../../../widgets/warehouse/wh_mobile_theme.dart';
import '../../main_layout.dart' show ScreenRefreshNotifier;

class WhMobilePurchaseReturnEditor extends StatefulWidget {
  const WhMobilePurchaseReturnEditor({super.key, this.docId});

  final String? docId;

  @override
  State<WhMobilePurchaseReturnEditor> createState() =>
      _WhMobilePurchaseReturnEditorState();
}

class _Line {
  _Line({
    required this.productId,
    required this.name,
    this.code,
    this.unit,
    this.variantId,
    double qty = 1,
    double cost = 0,
  })  : qty = qty,
        cost = cost;

  final String productId;
  final String? variantId;
  final String name;
  final String? code;
  final String? unit;
  double qty;
  double cost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'qty': qty,
        'costPrice': cost,
      };
}

class _WhMobilePurchaseReturnEditorState extends State<WhMobilePurchaseReturnEditor> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  bool _loading = true;
  bool _saving = false;
  String? _returnId;
  String _returnNo = '';
  String _status = 'Draft';
  String? _supplierId;
  List<PosSupplierFull> _suppliers = [];
  final List<_Line> _lines = [];
  DateTime _returnDate = DateTime.now();

  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _returnId = widget.docId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final sup = await _api.getPosPurchaseSuppliers(pageSize: 200);
    if (mounted && sup['isSuccess'] == true && sup['data'] is Map) {
      _suppliers = ((sup['data'] as Map)['items'] as List? ?? [])
          .map((e) => PosSupplierFull.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (_returnId != null && _returnId!.isNotEmpty) {
      final res = await _api.getPosPurchaseReturn(_returnId!);
      if (mounted && res['isSuccess'] == true) {
        final r = PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
        _returnNo = r.returnNo;
        _status = r.status;
        _supplierId = r.supplierId;
        _noteCtrl.text = r.note ?? '';
        _returnDate = r.returnDate ?? DateTime.now();
        _lines
          ..clear()
          ..addAll(r.lines.map((l) => _Line(
                productId: l.productId,
                variantId: l.variantId,
                name: l.productName,
                code: l.productCode,
                unit: l.unitName,
                qty: l.qty,
                cost: l.costPrice,
              )));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    if (_lines.any((l) => l.productId == pick.product.id)) return;
    setState(() {
      _lines.add(_Line(
        productId: pick.product.id,
        variantId: pick.variantId,
        name: pick.product.name,
        code: pick.product.productCode,
        unit: pick.unitLabel ?? pick.product.baseUnitName,
        qty: 1,
        cost: pick.product.costPrice,
      ));
    });
  }

  Future<void> _scan() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _pickProduct(pick);
  }

  Map<String, dynamic> _body({required bool complete}) => {
        'supplierId': _supplierId,
        'note': _noteCtrl.text.trim(),
        'returnDate': _returnDate.toUtc().toIso8601String(),
        'complete': complete,
        'lines': _lines.map((l) => l.toJson()).toList(),
      };

  Future<void> _save({required bool complete}) async {
    if (_supplierId == null) {
      NotificationOverlayManager().showWarning(title: 'NCC', message: 'Chọn nhà cung cấp');
      return;
    }
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: 'Thêm hàng cần trả');
      return;
    }
    setState(() => _saving = true);
    Map<String, dynamic> res;
    if (_returnId != null && _returnId!.isNotEmpty) {
      res = await _api.updatePosPurchaseReturn(_returnId!, _body(complete: complete));
    } else {
      res = await _api.createPosPurchaseReturn(_body(complete: complete));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      final r = PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager().showSuccess(
        title: complete ? 'Đã trả hàng' : 'Đã lưu nháp',
        message: r.returnNo,
      );
      if (complete) {
        ScreenRefreshNotifier.refreshPosAfterStockChange();
      }
      if (complete && mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.qty * l.cost);

  @override
  Widget build(BuildContext context) {
    return WhMobileScaffold(
      title: _returnNo.isEmpty ? 'Tạo phiếu trả' : _returnNo,
      subtitle: 'Trả hàng nhập',
      actions: [
        if (!_readOnly)
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            color: WhMobileTheme.primary,
            onPressed: _scan,
          ),
      ],
      bottomBar: WhMobileBottomBar(
        readOnly: _readOnly,
        loading: _saving,
        onSaveDraft: _readOnly ? null : () => _save(complete: false),
        onComplete: _readOnly ? null : () => _save(complete: true),
        completeLabel: 'Hoàn thành trả',
      ),
      body: _loading
          ? const Center(child: LoadingWidget())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                WhMobileTheme.padH,
                WhMobileTheme.gap,
                WhMobileTheme.padH,
                24,
              ),
              children: [
                WhGlassCard(
                  child: DropdownButtonFormField<String>(
                    value: _supplierId,
                    decoration: WhMobileTheme.fieldDecoration(label: 'Nhà cung cấp *'),
                    items: _suppliers
                        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: _readOnly ? null : (v) => setState(() => _supplierId = v),
                  ),
                ),
                const SizedBox(height: WhMobileTheme.gap),
                if (!_readOnly)
                  PosPurchaseProductSearchBar(
                    api: _api,
                    hintText: 'Tìm hàng cần trả…',
                    onPick: _pickProduct,
                  ),
                const SizedBox(height: WhMobileTheme.gap),
                WhSectionHeader(title: 'Hàng trả (${_lines.length})'),
                ...List.generate(_lines.length, (i) {
                  final l = _lines[i];
                  return WhLineCard(
                    index: i + 1,
                    name: l.name,
                    code: l.code,
                    unit: l.unit,
                    readOnly: _readOnly,
                    onRemove: _readOnly
                        ? null
                        : () => setState(() => _lines.removeAt(i)),
                    child: WhQtyStepper(
                      label: 'SL trả',
                      value: l.qty,
                      readOnly: _readOnly,
                      onChanged: (v) => setState(() => l.qty = v),
                    ),
                    trailing: Text(
                      _moneyFmt.format(l.qty * l.cost),
                      style: WhMobileTheme.money.copyWith(fontSize: 15),
                    ),
                  );
                }),
                const SizedBox(height: WhMobileTheme.gap),
                WhGlassCard(
                  child: Column(
                    children: [
                      WhSummaryRow(label: 'Tổng trả', value: '${_moneyFmt.format(_total)} đ', bold: true),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteCtrl,
                        readOnly: _readOnly,
                        maxLines: 2,
                        decoration: WhMobileTheme.fieldDecoration(label: 'Ghi chú'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
