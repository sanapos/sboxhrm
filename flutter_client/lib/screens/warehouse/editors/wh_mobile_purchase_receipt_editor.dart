import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/pos_purchase.dart';
import '../../../services/api_service.dart';
import '../../../utils/pos_mutation_result.dart';
import '../../../utils/pos_purchase_product_lookup.dart';
import '../../../utils/pos_sell_stock_patch.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/notification_overlay.dart';
import '../../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../../../widgets/pos_barcode_scanner.dart';
import '../../../widgets/warehouse/wh_mobile_components.dart';
import '../../../widgets/warehouse/wh_mobile_theme.dart';
import '../../main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class WhMobilePurchaseReceiptEditor extends StatefulWidget {
  const WhMobilePurchaseReceiptEditor({super.key, this.docId});

  final String? docId;

  @override
  State<WhMobilePurchaseReceiptEditor> createState() =>
      _WhMobilePurchaseReceiptEditorState();
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
        'discountAmount': 0,
        'unitName': unit ?? 'Cái',
      };
}

class _WhMobilePurchaseReceiptEditorState extends State<WhMobilePurchaseReceiptEditor> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: tr('0'));
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  bool _loading = true;
  bool _saving = false;
  String? _receiptId;
  String _receiptNo = '';
  String _status = 'Draft';
  String? _supplierId;
  String _paymentMethod = 'Tiền mặt';
  List<PosSupplierFull> _suppliers = [];
  final List<_Line> _lines = [];
  DateTime _importDate = DateTime.now();

  static const _paymentMethods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ'];

  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _receiptId = widget.docId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final sup = await _api.getPosPurchaseSuppliers(pageSize: 200);
    if (mounted && sup['isSuccess'] == true && sup['data'] is Map) {
      _suppliers = ((sup['data'] as Map)['items'] as List? ?? [])
          .map((e) => PosSupplierFull.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (_receiptId != null && _receiptId!.isNotEmpty) {
      final res = await _api.getPosPurchaseReceipt(_receiptId!);
      if (mounted && res['isSuccess'] == true) {
        final r = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
        _receiptNo = r.receiptNo;
        _status = r.status;
        _supplierId = r.supplierId;
        _noteCtrl.text = r.note ?? '';
        _paidCtrl.text = r.paidAmount.toStringAsFixed(0);
        _importDate = r.importDate ?? DateTime.now();
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

  double get _linesTotal => _lines.fold(0.0, (s, l) => s + l.qty * l.cost);
  double get _paid => double.tryParse(_paidCtrl.text.replaceAll(',', '')) ?? 0;

  Map<String, dynamic> _body({required bool complete}) => {
        'supplierId': _supplierId,
        'note': _noteCtrl.text.trim(),
        'discountAmount': 0,
        'paidAmount': _paid,
        'paymentMethod': _paymentMethod,
        'importDate': _importDate.toUtc().toIso8601String(),
        'complete': complete,
        'lines': _lines.map((l) => l.toJson()).toList(),
      };

  Future<void> _save({required bool complete}) async {
    if (_supplierId == null) {
      NotificationOverlayManager().showWarning(title: 'NCC', message: tr('Chọn nhà cung cấp'));
      return;
    }
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm hàng nhập'));
      return;
    }
    setState(() => _saving = true);
    Map<String, dynamic> res;
    if (_receiptId != null && _receiptId!.isNotEmpty) {
      res = await _api.updatePosPurchaseReceipt(_receiptId!, _body(complete: complete));
    } else {
      res = await _api.createPosPurchaseReceipt(_body(complete: complete));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      if (complete) {
        final check = PosDocMutationResult.parse(
          Map<String, dynamic>.from(res),
          expectedStatus: 'Completed',
          completedLabel: 'Đã nhập hàng',
        );
        if (!check.ok) {
          NotificationOverlayManager().showError(
              title: 'Lỗi', message: check.errorMessage ?? 'Không hoàn thành được');
          return;
        }
        ScreenRefreshNotifier.refreshPosAfterStockChange(
          sellStockLines: _lines
              .map((l) => PosSellStockLineDelta(productId: l.productId, qty: l.qty, addBack: true))
              .toList(),
        );
      } else {
        ScreenRefreshNotifier.refreshPosPurchaseReceipts();
      }
      final r = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager().showSuccess(
        title: complete ? 'Đã nhập hàng' : 'Đã lưu nháp',
        message: r.receiptNo,
      );
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WhMobileScaffold(
      title: _receiptNo.isEmpty ? 'Tạo phiếu nhập' : _receiptNo,
      subtitle: 'Nhập hàng NCC',
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
        completeLabel: 'Hoàn thành nhập',
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
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _supplierId,
                        decoration: WhMobileTheme.fieldDecoration(label: 'Nhà cung cấp *'),
                        items: _suppliers
                            .map((s) => DropdownMenuItem(value: s.id, child: Text(tr(s.name))))
                            .toList(),
                        onChanged: _readOnly ? null : (v) => setState(() => _supplierId = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        decoration: WhMobileTheme.fieldDecoration(label: 'Thanh toán'),
                        items: _paymentMethods
                            .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
                            .toList(),
                        onChanged: _readOnly ? null : (v) => setState(() => _paymentMethod = v ?? 'Tiền mặt'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: WhMobileTheme.gap),
                if (!_readOnly)
                  PosPurchaseProductSearchBar(
                    api: _api,
                    hintText: tr('Tìm hoặc quét mã hàng…'),
                    onPick: _pickProduct,
                  ),
                const SizedBox(height: WhMobileTheme.gap),
                WhSectionHeader(title: 'Hàng nhập (${_lines.length})'),
                if (_lines.isEmpty)
                  const WhEmptyState(
                    icon: Icons.move_to_inbox_rounded,
                    title: 'Chưa có hàng',
                    subtitle: 'Quét mã hoặc tìm sản phẩm',
                  )
                else
                  ...List.generate(_lines.length, (i) {
                    final l = _lines[i];
                    return WhLineCard(
                      index: i + 1,
                      name: l.name,
                      code: l.code,
                      unit: l.unit,
                      readOnly: _readOnly,
                      onRemove: _readOnly ? null : () => setState(() => _lines.removeAt(i)),
                      child: Column(
                        children: [
                          WhQtyStepper(
                            label: 'Số lượng',
                            value: l.qty,
                            readOnly: _readOnly,
                            onChanged: (v) => setState(() => l.qty = v),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: _readOnly
                                ? null
                                : () async {
                                    final ctrl = TextEditingController(
                                        text: tr(l.cost.toStringAsFixed(0)));
                                    final v = await showDialog<String>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(tr('Giá nhập')),
                                        content: TextField(
                                          controller: ctrl,
                                          keyboardType: TextInputType.number,
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: Text(tr('Hủy'))),
                                          FilledButton(
                                              onPressed: () => Navigator.pop(ctx, ctrl.text),
                                              child: Text(tr('OK'))),
                                        ],
                                      ),
                                    );
                                    if (v != null) {
                                      setState(() =>
                                          l.cost = double.tryParse(v.replaceAll(',', '')) ?? l.cost);
                                    }
                                  },
                            borderRadius: BorderRadius.circular(WhMobileTheme.radiusSm),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: WhMobileTheme.bg,
                                borderRadius: BorderRadius.circular(WhMobileTheme.radiusSm),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(tr('Giá nhập'), style: WhMobileTheme.label),
                                  Text(tr('${_moneyFmt.format(l.cost)} đ'),
                                    style: WhMobileTheme.body.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: Text(
                        tr(_moneyFmt.format(l.qty * l.cost)),
                        style: WhMobileTheme.money.copyWith(fontSize: 15),
                      ),
                    );
                  }),
                const SizedBox(height: WhMobileTheme.gap),
                WhGlassCard(
                  child: Column(
                    children: [
                      WhSummaryRow(label: 'Tổng hàng', value: '${_moneyFmt.format(_linesTotal)} đ', bold: true),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _paidCtrl,
                        readOnly: _readOnly,
                        keyboardType: TextInputType.number,
                        decoration: WhMobileTheme.fieldDecoration(label: 'Đã trả NCC'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      WhSummaryRow(
                        label: 'Còn nợ',
                        value: '${_moneyFmt.format((_linesTotal - _paid).clamp(0, double.infinity))} đ',
                        color: WhMobileTheme.warning,
                      ),
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
