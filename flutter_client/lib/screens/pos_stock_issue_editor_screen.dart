import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_stock_issue_doc.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_stock_issue_config.dart';
import '../widgets/pos/pos_stock_issue_helpers.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos_barcode_scanner.dart';

const _blue = Color(0xFF2563EB);

class _IssueLine {
  final String lineId;
  final String productId;
  final String? variantId;
  final String productCode;
  final String productName;
  final String unitName;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;

  _IssueLine({
    required this.lineId,
    required this.productId,
    this.variantId,
    required this.productCode,
    required this.productName,
    this.unitName = 'Cái',
    double qty = 0,
    double costPrice = 0,
  })  : qtyCtrl = TextEditingController(
            text: qty == qty.roundToDouble()
                ? qty.toStringAsFixed(0)
                : qty.toStringAsFixed(2)),
        costCtrl = TextEditingController(text: costPrice.toStringAsFixed(0));

  double get qty => double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0;
  double get costPrice => double.tryParse(costCtrl.text.replaceAll(',', '')) ?? 0;
  double get lineTotal => qty * costPrice;

  Map<String, dynamic> toUpdateJson() => {
        'lineId': lineId,
        'qty': qty,
        'costPrice': costPrice,
      };

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }

  factory _IssueLine.fromApi(PosStockIssueLine ln) => _IssueLine(
        lineId: ln.id,
        productId: ln.productId,
        variantId: ln.variantId,
        productCode: ln.productCode,
        productName: ln.productName,
        unitName: ln.unitName ?? 'Cái',
        qty: ln.qty,
        costPrice: ln.costPrice,
      );
}

class PosStockIssueEditorScreen extends StatefulWidget {
  const PosStockIssueEditorScreen({
    super.key,
    required this.config,
    this.issueId,
  });

  final PosStockIssueConfig config;
  final String? issueId;

  @override
  State<PosStockIssueEditorScreen> createState() =>
      _PosStockIssueEditorScreenState();
}

class _PosStockIssueEditorScreenState extends State<PosStockIssueEditorScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _issueNoCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');

  bool _loading = true;
  bool _saving = false;
  String? _issueId;
  String _issueNo = '';
  String _status = 'Draft';
  String? _categoryName;
  final List<_IssueLine> _lines = [];

  PosStockIssueConfig get _config => widget.config;
  bool get _readOnly => _status != 'Draft';

  @override
  void initState() {
    super.initState();
    _issueId = widget.issueId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _issueNoCtrl.dispose();
    _recipientCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    if (_issueId != null && _issueId!.isNotEmpty) {
      await _loadIssue(_issueId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyDoc(PosStockIssueDoc doc) {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ln in doc.lines) {
      _lines.add(_IssueLine.fromApi(ln));
    }
    _issueId = doc.id.isEmpty ? null : doc.id;
    _issueNo = doc.issueNo;
    _issueNoCtrl.text = doc.issueNo;
    _status = doc.status;
    _noteCtrl.text = doc.note ?? '';
    _categoryName = doc.categoryName;
    _recipientCtrl.text = doc.recipientName ?? '';
  }

  Future<void> _loadIssue(String id) async {
    final res = await _api.getPosStockIssueDoc(_config.kind, id);
    if (!mounted || res['isSuccess'] != true) return;
    setState(() => _applyDoc(
        PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>)));
  }

  Future<String?> _ensureIssueId() async {
    if (_issueId != null && _issueId!.isNotEmpty) return _issueId;
    final res = await _api.createPosStockIssueDoc(_config.kind);
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không tạo được phiếu');
      return null;
    }
    final doc =
        PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>);
    setState(() {
      _issueId = doc.id;
      _issueNo = doc.issueNo;
      _issueNoCtrl.text = doc.issueNo;
      _status = doc.status;
    });
    return doc.id;
  }

  double get _totalValue => _lines.fold(0.0, (a, l) => a + l.lineTotal);
  double get _totalQty => _lines.fold(0.0, (a, l) => a + l.qty);

  String _fmtQty(double v) => _qtyFmt.format(v);

  Map<String, dynamic> _headerBody() => {
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (_config.showInternalFields) ...{
          'categoryName': _categoryName,
          'recipientName': _recipientCtrl.text.trim().isEmpty
              ? null
              : _recipientCtrl.text.trim(),
        },
      };

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    final issueId = await _ensureIssueId();
    if (issueId == null || !mounted) return;

    final key = '${pick.product.id}:${pick.variantId ?? 'base'}';
    if (_lines.any((l) => '${l.productId}:${l.variantId ?? 'base'}' == key)) {
      NotificationOverlayManager()
          .showWarning(title: 'Trùng', message: 'Hàng đã có trong phiếu');
      return;
    }

    final res = await _api.addPosStockIssueDocLines(_config.kind, issueId, [
      {
        'productId': pick.product.id,
        if (pick.variantId != null) 'variantId': pick.variantId,
      },
    ]);

    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      _applyDoc(
          PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>));
      setState(() {});
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không thêm được hàng');
    }
  }

  Future<void> _scanBarcode() async {
    if (_readOnly) return;
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _onPickProduct(pick);
  }

  Future<void> _removeLine(_IssueLine line) async {
    if (_readOnly || _issueId == null) return;
    final res =
        await _api.removePosStockIssueDocLine(_config.kind, _issueId!, line.lineId);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      _applyDoc(
          PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>));
      setState(() {});
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được dòng');
    }
  }

  void _adjustQty(_IssueLine line, double delta) {
    final next = (line.qty + delta).clamp(0, double.infinity);
    line.qtyCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  Future<bool> _saveLinesAndHeader() async {
    if ((_issueId == null || _issueId!.isEmpty) && _lines.isEmpty) {
      return false;
    }

    final issueId = await _ensureIssueId();
    if (issueId == null) return false;

    if (_lines.isNotEmpty) {
      final lineRes = await _api.updatePosStockIssueDocLines(
        _config.kind,
        issueId,
        _lines.map((l) => l.toUpdateJson()).toList(),
      );
      if (lineRes['isSuccess'] != true) {
        NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: lineRes['message']?.toString() ?? 'Không lưu được dòng');
        return false;
      }
      _applyDoc(
          PosStockIssueDoc.fromJson(lineRes['data'] as Map<String, dynamic>));
    }

    final headerRes =
        await _api.updatePosStockIssueDoc(_config.kind, issueId, _headerBody());
    if (headerRes['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: headerRes['message']?.toString() ?? 'Không lưu được thông tin phiếu');
      return false;
    }
    _applyDoc(
        PosStockIssueDoc.fromJson(headerRes['data'] as Map<String, dynamic>));
    return true;
  }

  Future<void> _saveDraft() async {
    if (_lines.isEmpty && (_issueId == null || _issueId!.isEmpty)) {
      NotificationOverlayManager().showWarning(
          title: 'Phiếu trống',
          message: 'Thêm ít nhất một dòng hàng trước khi lưu');
      return;
    }
    setState(() => _saving = true);
    final ok = await _saveLinesAndHeader();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã lưu phiếu tạm', message: _issueNo);
    }
  }

  Future<void> _complete() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Phiếu trống', message: 'Thêm ít nhất một dòng hàng');
      return;
    }
    if (_lines.every((l) => l.qty <= 0)) {
      NotificationOverlayManager().showWarning(
          title: 'Số lượng', message: 'Nhập số lượng xuất > 0 cho ít nhất một dòng');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_config.completeDialogTitle),
        content: Text(_config.completeDialogMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    final saved = await _saveLinesAndHeader();
    if (!saved || !mounted) {
      setState(() => _saving = false);
      return;
    }

    final res = await _api.completePosStockIssueDoc(_config.kind, _issueId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Hoàn thành', message: _issueNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không hoàn thành được');
    }
  }

  Future<void> _deleteDraft() async {
    if (_issueId == null || _issueId!.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text('Xóa hẳn phiếu $_issueNo?'),
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
    final res = await _api.deletePosStockIssueDoc(_config.kind, _issueId!);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: _issueNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
    }
  }

  Future<void> _voidCompleted() async {
    if (_issueId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_config.voidDialogTitle),
        content: Text(_config.voidDialogMessage),
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
    final res = await _api.cancelPosStockIssueDoc(_config.kind, _issueId!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy', message: 'Đã hoàn tồn kho · $_issueNo');
      await _loadIssue(_issueId!);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  Widget _qtyCell(_IssueLine l) {
    if (_readOnly) {
      return Text(_fmtQty(l.qty), style: const TextStyle(fontSize: 13));
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

  Widget _costCell(_IssueLine l) {
    if (_readOnly) {
      return Text('${_moneyFmt.format(l.costPrice)} đ',
          style: const TextStyle(fontSize: 13));
    }
    return TextField(
      controller: l.costCtrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        suffixText: 'đ',
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildLinesTable() {
    if (posUseMobileList(context)) {
      return _buildMobileLinesList();
    }
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
                headerCell('Mã', 2),
                headerCell('Tên', 4),
                headerCell('ĐVT', 1),
                headerCell(_config.qtyColumnLabel, 3),
                headerCell('Giá vốn', 2),
                headerCell('Thành tiền', 2),
                if (!_readOnly) const SizedBox(width: 40),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Text(
                    'Chưa có hàng trong phiếu',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  itemCount: _lines.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
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
                              Text(l.productName,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w500)),
                              4),
                          dataCell(Text(l.unitName, style: const TextStyle(fontSize: 13)), 1),
                          dataCell(_qtyCell(l), 3),
                          dataCell(_costCell(l), 2),
                          dataCell(
                              Text('${_moneyFmt.format(l.lineTotal)} đ',
                                  style: const TextStyle(fontSize: 13)),
                              2),
                          if (!_readOnly)
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _removeLine(l),
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

  Widget _buildMobileLinesList() {
    if (_lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Chưa có hàng trong phiếu',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      itemCount: _lines.length,
      itemBuilder: (_, i) {
        final l = _lines[i];
        return PosMobileLineItemCard(
          index: i + 1,
          code: l.productCode,
          name: l.productName,
          onRemove: _readOnly ? null : () => _removeLine(l),
          fields: [
            Text('ĐVT: ${l.unitName}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            _qtyCell(l),
            const SizedBox(height: 8),
            _costCell(l),
            const SizedBox(height: 6),
            Text(
              'Thành tiền: ${_moneyFmt.format(l.lineTotal)} đ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          if (!_readOnly)
            Expanded(
              child: PosPurchaseProductSearchBar(
                api: _api,
                readOnly: _readOnly,
                hintText: 'Tìm hàng hóa (F3)',
                onPick: _onPickProduct,
              ),
            )
          else
            Expanded(
              child: Text('Chi tiết phiếu ${_config.title}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            tooltip: 'Quét mã vạch',
            icon: const Icon(Icons.qr_code_scanner_outlined),
            onPressed: _readOnly ? null : _scanBarcode,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _issueNoCtrl,
          readOnly: true,
          decoration: PosTheme.inputDecoration(
            label: 'Mã phiếu',
            hint: 'Mã phiếu tự động',
          ),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: PosTheme.inputDecoration(label: 'Trạng thái'),
          child: stockIssueStatusChip(_status),
        ),
        if (_config.showInternalFields) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _categoryName != null &&
                    kInternalUseCategories.contains(_categoryName)
                ? _categoryName
                : null,
            decoration: PosTheme.inputDecoration(label: 'Loại xuất'),
            items: kInternalUseCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged:
                _readOnly ? null : (v) => setState(() => _categoryName = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recipientCtrl,
            readOnly: _readOnly,
            decoration: PosTheme.inputDecoration(label: 'Người nhận'),
          ),
        ],
        const Divider(height: 24),
        _totalRow('Tổng SL (${_lines.length})', _fmtQty(_totalQty)),
        _totalRow('Tổng giá trị', '${_moneyFmt.format(_totalValue)} đ',
            bold: true),
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
            onPressed: _saving ? null : _saveDraft,
            child: Text(_saving ? '…' : 'Lưu tạm'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _complete,
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: Text(_saving ? '…' : 'Hoàn thành'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _deleteDraft,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Xóa phiếu'),
          ),
        ] else if (_status == 'Cancelled') ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _saving ? null : _deleteDraft,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Xóa phiếu'),
          ),
        ] else if (_status == 'Completed') ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _saving ? null : _voidCompleted,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Hủy phiếu'),
          ),
        ],
      ],
    );
  }

  Widget? _buildMobileActionBar() {
    if (_readOnly || !posUseMobileList(context)) return null;
    return PosMobileEditorActionBar(
      children: [
        OutlinedButton(
          onPressed: _saving ? null : _saveDraft,
          child: const Text('Lưu tạm'),
        ),
        FilledButton(
          onPressed: _saving ? null : _complete,
          style: FilledButton.styleFrom(backgroundColor: _blue),
          child: const Text('Hoàn thành'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canEdit('PosProducts')) {
      return Scaffold(
          body: Center(child: Text('Không có quyền ${_config.title}')));
    }

    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.f3): _IssueSearchIntent()},
      child: Actions(
        actions: {
          _IssueSearchIntent: CallbackAction<_IssueSearchIntent>(onInvoke: (_) => null),
        },
        child: Scaffold(
          backgroundColor: HrmPageChrome.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: PosTheme.textPrimary,
            elevation: 0,
            title: Row(
              children: [
                Icon(_config.icon, color: _blue, size: 22),
                const SizedBox(width: 8),
                Text(_issueId == null
                    ? _config.title
                    : '${_config.title} · $_issueNo'),
              ],
            ),
          ),
          body: _loading
              ? const LoadingWidget()
              : posUseMobileList(context)
                  ? posMobileEditorScrollBody(
                      searchBar: _buildSearchBar(),
                      lines: ColoredBox(
                        color: Colors.white,
                        child: _buildLinesTable(),
                      ),
                      metaPanel: _buildMetaPanel(),
                      actionBar: _buildMobileActionBar(),
                    )
                  : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _buildSearchBar(),
                          Expanded(
                            child: ColoredBox(
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
                      child: SingleChildScrollView(child: _buildMetaPanel()),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  fontSize: bold ? 15 : 13)),
        ],
      ),
    );
  }
}

class _IssueSearchIntent extends Intent {
  const _IssueSearchIntent();
}
