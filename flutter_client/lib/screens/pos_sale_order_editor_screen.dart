import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_customer.dart';
import '../models/pos_product.dart';
import '../models/pos_sale_order.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../utils/pos_print_store_info.dart';
import '../utils/pos_sale_order_print.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_customer_form_dialog.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos_barcode_scanner.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

enum _SaleLineColumn {
  stt('STT'),
  code('Mã hàng'),
  name('Tên hàng'),
  unit('ĐVT'),
  qty('Số lượng'),
  price('Đơn giá'),
  total('Thành tiền');

  const _SaleLineColumn(this.label);
  final String label;
}

Set<_SaleLineColumn> _defaultSaleColumns() => {
      _SaleLineColumn.stt,
      _SaleLineColumn.code,
      _SaleLineColumn.name,
      _SaleLineColumn.unit,
      _SaleLineColumn.qty,
      _SaleLineColumn.price,
      _SaleLineColumn.total,
    };

class _EditorLine {
  final String productId;
  final String productCode;
  final String productName;
  final String baseUnitName;
  String? variantId;
  List<PosProductVariant> variants;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  _EditorLine({
    required this.productId,
    required this.productCode,
    required this.productName,
    this.baseUnitName = 'Cái',
    this.variantId,
    this.variants = const [],
    double qty = 1,
    double price = 0,
  })  : qtyCtrl = TextEditingController(text: tr(qty.toStringAsFixed(0))),
        priceCtrl = TextEditingController(text: tr(price.toStringAsFixed(0)));

  double get lineTotal {
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;
    return qty * price;
  }

  Map<String, dynamic> toInputJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'qty': double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0,
        'unitPrice': double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0,
      };

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

class PosSaleOrderEditorScreen extends StatefulWidget {
  const PosSaleOrderEditorScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<PosSaleOrderEditorScreen> createState() => _PosSaleOrderEditorScreenState();
}

class _PosSaleOrderEditorScreenState extends State<PosSaleOrderEditorScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: tr('0'));
  final _paidCtrl = TextEditingController(text: tr('0'));
  final _deliveryAddressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  String _paymentMethod = 'Tiền mặt';
  static const _paymentMethods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ'];
  static const _deliveryStatuses = ['Chờ giao', 'Đang giao', 'Đã giao', 'Không giao được'];
  static const _deliveryPartners = ['Tự giao', 'GHN', 'GHTK', 'Viettel Post', 'J&T'];

  bool _loading = true;
  bool _saving = false;
  String? _orderId;
  String _orderNo = '';
  String _status = 'Draft';
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  List<PosCustomer> _customers = [];
  bool _isDelivery = false;
  String _deliveryStatus = 'Chờ giao';
  String _deliveryPartner = 'Tự giao';
  final List<_EditorLine> _lines = [];
  Set<_SaleLineColumn> _visibleColumns = _defaultSaleColumns();

  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _orderId = widget.orderId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await _loadCustomers();
    if (_orderId != null && _orderId!.isNotEmpty) {
      await _loadOrder(_orderId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCustomers() async {
    final res = await _api.getPosCustomers(pageSize: 200);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final items = (res['data'] as Map)['items'] as List? ?? [];
    setState(() {
      _customers = items
          .map((e) => PosCustomer.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  String _customerDisplayLabel() {
    final fromList = _customers.where((c) => c.id == _customerId).firstOrNull;
    if (fromList != null) {
      return '${fromList.customerCode} — ${fromList.name}';
    }
    final name = _customerName?.trim();
    if (name != null && name.isNotEmpty) {
      final phone = _customerPhone?.trim();
      if (phone != null && phone.isNotEmpty) return '$name · $phone';
      return name;
    }
    return 'Bán cho người tiêu dùng';
  }

  Future<void> _loadOrder(String id) async {
    final res = await _api.getPosSale(id);
    if (!mounted || res['isSuccess'] != true) return;
    final o = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ln in o.lines) {
      final parts = ln.productName.split(' — ');
      final line = _EditorLine(
        productId: ln.productId,
        productCode: '',
        productName: parts.length > 1 ? parts.sublist(1).join(' — ') : ln.productName,
        baseUnitName: ln.unitName ?? 'Cái',
        variantId: ln.variantId,
        qty: ln.qty,
        price: ln.unitPrice,
      );
      await _loadVariantsForLine(line);
      _lines.add(line);
    }
    setState(() {
      _orderId = o.id;
      _orderNo = o.orderNo;
      _status = o.status;
      _customerId = o.customerId;
      _customerName = o.customerName;
      _customerPhone = o.customerPhone;
      _isDelivery = o.isDelivery;
      _deliveryStatus = o.deliveryStatus ?? 'Chờ giao';
      _deliveryPartner = o.deliveryPartner ?? 'Tự giao';
      _noteCtrl.text = o.note ?? '';
      _discountCtrl.text = o.discount.toStringAsFixed(0);
      _paidCtrl.text = o.paidAmount.toStringAsFixed(0);
      _paymentMethod = o.paymentMethod;
      _deliveryAddressCtrl.text = o.deliveryAddress ?? '';
      _deliveryPhoneCtrl.text = o.deliveryPhone ?? '';
    });
  }

  Future<void> _loadVariantsForLine(_EditorLine line) async {
    if (line.variants.isNotEmpty) return;
    final vRes = await _api.getPosProductVariants(line.productId);
    if (vRes['isSuccess'] == true && vRes['data'] is List) {
      line.variants = (vRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  double get _subTotal => _lines.fold(0.0, (a, l) => a + l.lineTotal);

  double get _discount =>
      double.tryParse(_discountCtrl.text.replaceAll(',', '')) ?? 0;

  double get _grandTotal => (_subTotal - _discount).clamp(0, double.infinity);

  double get _paidAmount =>
      double.tryParse(_paidCtrl.text.replaceAll(',', '')) ?? 0;

  Future<void> _addLine(PosProduct product, {String? preselectVariantId}) async {
    if (_readOnly) return;
    final line = _EditorLine(
      productId: product.id,
      productCode: product.productCode,
      productName: product.name,
      baseUnitName: product.baseUnitName,
      variantId: preselectVariantId,
      price: product.basePrice,
    );
    await _loadVariantsForLine(line);
    if (preselectVariantId == null && line.variants.length == 1) {
      line.variantId = line.variants.first.id;
      line.priceCtrl.text = line.variants.first.basePrice.toStringAsFixed(0);
    }
    setState(() => _lines.add(line));
  }

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    await _addLine(pick.product, preselectVariantId: pick.variantId);
  }

  Future<void> _scanBarcode() async {
    if (_readOnly) return;
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _onPickProduct(pick);
  }

  Future<void> _openAddCustomer() async {
    if (_readOnly) return;
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => const PosCustomerFormDialog(),
    );
    if (created == null || !mounted) return;
    await _loadCustomers();
    if (created is Map && created['id'] != null) {
      setState(() => _customerId = created['id'].toString());
    }
  }

  Map<String, dynamic> _buildBody({required bool complete}) {
    final customer = _customers.where((c) => c.id == _customerId).firstOrNull;
    return {
      'lines': _lines.map((l) => l.toInputJson()).toList(),
      'discount': _discount,
      'paidAmount': _paidAmount,
      'paymentMethod': _paymentMethod,
      'customerId': _customerId,
      'customerName': customer?.name,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'complete': complete,
      'isDelivery': _isDelivery,
      if (_isDelivery) ...{
        'deliveryAddress': _deliveryAddressCtrl.text.trim(),
        'deliveryPhone': _deliveryPhoneCtrl.text.trim(),
        'deliveryPartner': _deliveryPartner,
        'deliveryStatus': _deliveryStatus,
      },
    };
  }

  Future<void> _save({required bool complete}) async {
    if (_lines.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'Đơn trống', message: tr('Thêm ít nhất một dòng hàng'));
      return;
    }
    setState(() => _saving = true);
    final body = _buildBody(complete: complete);
    Map<String, dynamic> res;
    if (_orderId != null && _orderId!.isNotEmpty) {
      res = await _api.updatePosSale(_orderId!, body);
    } else {
      res = await _api.createPosSale(body);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      final o = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager().showSuccess(
        title: complete ? 'Hoàn thành đơn' : 'Đã lưu phiếu tạm',
        message: o.orderNo,
      );
      if (complete) {
        ScreenRefreshNotifier.refreshPosAfterStockChange();
      }
      if (complete && mounted) {
        Navigator.pop(context, true);
      } else {
        await _loadOrder(o.id);
      }
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _completeExisting() async {
    if (_orderId == null) return;
    setState(() => _saving = true);
    final res = await _api.completePosSale(_orderId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Hoàn tất', message: tr('Đơn đã hoàn thành'));
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Tùy chọn hiển thị')),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _SaleLineColumn.values.map((c) {
                return CheckboxListTile(
                  dense: true,
                  activeColor: _blue,
                  title: Text(tr(c.label), style: const TextStyle(fontSize: 13)),
                  value: _visibleColumns.contains(c),
                  onChanged: (v) {
                    setDlg(() {
                      if (v == true) {
                        _visibleColumns.add(c);
                      } else if (_visibleColumns.length > 1) {
                        _visibleColumns.remove(c);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDlg(() => _visibleColumns = _defaultSaleColumns()),
              child: Text(tr('Mặc định')),
            ),
            FilledButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: Text(tr('Áp dụng')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosProducts')) {
      return Scaffold(body: Center(child: Text(tr('Không có quyền'))));
    }
    final canEdit = perm.canEdit('PosProducts');

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          const PosModuleToolbar(activeModule: 'PosSaleOrders'),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    tr(_orderId == null
                        ? 'Tạo đơn hàng mới'
                        : 'Đơn $_orderNo'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!_readOnly)
                  IconButton(
                    onPressed: _showColumnPicker,
                    icon: const Icon(Icons.view_column_outlined),
                    tooltip: tr('Tùy chọn cột'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingWidget()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_readOnly) ...[
                          PosPurchaseProductSearchBar(
                            api: _api,
                            onPick: _onPickProduct,
                            hintText: tr('Tìm hàng bán theo mã hoặc tên'),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _scanBarcode,
                              icon: const Icon(Icons.qr_code_scanner, size: 18),
                              label: Text(tr('Quét mã')),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildHeaderFields(),
                        const SizedBox(height: 12),
                        _buildLinesTable(),
                        const SizedBox(height: 12),
                        _buildTotals(),
                        const SizedBox(height: 16),
                        if (canEdit) _buildActions(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _readOnly
                      ? InputDecorator(
                          decoration: PosTheme.inputDecoration(label: 'Khách hàng'),
                          child: Text(
                            tr(_customerDisplayLabel()),
                            style: const TextStyle(fontSize: 14),
                          ),
                        )
                      : DropdownButtonFormField<String?>(
                          value: _customerId,
                          decoration: PosTheme.inputDecoration(label: 'Khách hàng'),
                          hint: Text(tr('Khách lẻ')),
                          items: [
                            DropdownMenuItem<String?>(
                                value: null, child: Text(tr('Khách lẻ'))),
                            ..._customers.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(tr('${c.customerCode} — ${c.name}'),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _customerId = v),
                        ),
                ),
                if (!_readOnly) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openAddCustomer,
                    icon: const Icon(Icons.person_add_outlined),
                    tooltip: tr('Thêm KH'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Giao hàng'), style: TextStyle(fontSize: 14)),
              value: _isDelivery,
              activeColor: _blue,
              onChanged: _readOnly ? null : (v) => setState(() => _isDelivery = v),
            ),
            if (_isDelivery) ...[
              TextField(
                controller: _deliveryAddressCtrl,
                readOnly: _readOnly,
                decoration: PosTheme.inputDecoration(label: 'Địa chỉ giao hàng'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deliveryPhoneCtrl,
                      readOnly: _readOnly,
                      decoration: PosTheme.inputDecoration(label: 'SĐT nhận hàng'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _deliveryPartner,
                      decoration: PosTheme.inputDecoration(label: 'Đối tác GH'),
                      items: _deliveryPartners
                          .map((p) => DropdownMenuItem(value: p, child: Text(tr(p))))
                          .toList(),
                      onChanged: _readOnly ? null : (v) => setState(() => _deliveryPartner = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _deliveryStatus,
                decoration: PosTheme.inputDecoration(label: 'Trạng thái GH'),
                items: _deliveryStatuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(tr(s))))
                    .toList(),
                onChanged: _readOnly ? null : (v) => setState(() => _deliveryStatus = v!),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discountCtrl,
                    readOnly: _readOnly,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: PosTheme.inputDecoration(label: 'Giảm giá (VNĐ)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: PosTheme.inputDecoration(label: 'Thanh toán'),
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
                        .toList(),
                    onChanged: _readOnly ? null : (v) => setState(() => _paymentMethod = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _paidCtrl,
                    readOnly: _readOnly,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: PosTheme.inputDecoration(label: 'Khách trả'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              readOnly: _readOnly,
              decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinesTable() {
    if (_lines.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text(tr('Chưa có hàng — tìm hoặc quét mã để thêm'))),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          columns: [
            if (_visibleColumns.contains(_SaleLineColumn.stt))
              DataColumn(label: Text(tr('STT'))),
            if (_visibleColumns.contains(_SaleLineColumn.code))
              DataColumn(label: Text(tr('Mã'))),
            if (_visibleColumns.contains(_SaleLineColumn.name))
              DataColumn(label: Text(tr('Tên hàng'))),
            if (_visibleColumns.contains(_SaleLineColumn.unit))
              DataColumn(label: Text(tr('ĐVT'))),
            if (_visibleColumns.contains(_SaleLineColumn.qty))
              DataColumn(label: Text(tr('SL'))),
            if (_visibleColumns.contains(_SaleLineColumn.price))
              DataColumn(label: Text(tr('Đơn giá'))),
            if (_visibleColumns.contains(_SaleLineColumn.total))
              DataColumn(label: Text(tr('Thành tiền'))),
            if (!_readOnly) const DataColumn(label: Text('')),
          ],
          rows: List.generate(_lines.length, (i) {
            final line = _lines[i];
            return DataRow(cells: [
              if (_visibleColumns.contains(_SaleLineColumn.stt))
                DataCell(Text(tr('${i + 1}'))),
              if (_visibleColumns.contains(_SaleLineColumn.code))
                DataCell(Text(tr(line.productCode))),
              if (_visibleColumns.contains(_SaleLineColumn.name))
                DataCell(SizedBox(
                  width: 200,
                  child: Text(tr(line.productName), overflow: TextOverflow.ellipsis),
                )),
              if (_visibleColumns.contains(_SaleLineColumn.unit))
                DataCell(Text(tr(line.baseUnitName))),
              if (_visibleColumns.contains(_SaleLineColumn.qty))
                DataCell(SizedBox(
                  width: 72,
                  child: TextField(
                    controller: line.qtyCtrl,
                    readOnly: _readOnly,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                )),
              if (_visibleColumns.contains(_SaleLineColumn.price))
                DataCell(SizedBox(
                  width: 96,
                  child: TextField(
                    controller: line.priceCtrl,
                    readOnly: _readOnly,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                )),
              if (_visibleColumns.contains(_SaleLineColumn.total))
                DataCell(Text(tr('${_moneyFmt.format(line.lineTotal)} đ'))),
              if (!_readOnly)
                DataCell(IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      line.dispose();
                      _lines.removeAt(i);
                    });
                  },
                )),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _buildTotals() {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(tr('Tạm tính: ${_moneyFmt.format(_subTotal)} đ')),
          Text(tr('Giảm giá: ${_moneyFmt.format(_discount)} đ')),
          Text(tr('Tổng: ${_moneyFmt.format(_grandTotal)} đ'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(tr('Khách trả: ${_moneyFmt.format(_paidAmount)} đ')),
          Text(tr('Còn lại: ${_moneyFmt.format(_grandTotal - _paidAmount)} đ')),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_status == 'Draft') ...[
          OutlinedButton(
            onPressed: _saving ? null : () => _save(complete: false),
            child: Text(tr('Lưu tạm')),
          ),
          FilledButton(
            onPressed: _saving ? null : () => _save(complete: true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: Text(tr('Hoàn thành')),
          ),
          if (_orderId != null)
            OutlinedButton(
              onPressed: _saving ? null : _completeExisting,
              child: Text(tr('Hoàn thành (nhanh)')),
            ),
        ],
        if (_orderId != null && _status == 'Completed')
          OutlinedButton.icon(
            onPressed: () async {
              final res = await _api.getPosSale(_orderId!);
              if (!mounted || res['isSuccess'] != true) return;
              final o = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
              final store = await PosPrintStoreInfo.load();
              if (!mounted) return;
              await printPosSaleOrder(
                context: context,
                order: o,
                branchName: store.storeName,
                storeAddress: store.address,
                storePhone: store.phone,
                skipDedup: true,
                preferDevicePrintOnly: true,
                showFeedback: true,
              );
            },
            icon: const Icon(Icons.print, size: 16),
            label: Text(tr('In')),
          ),
      ],
    );
  }
}
