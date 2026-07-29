import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_stock_count.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_doc_status.dart';
import '../utils/pos_mutation_result.dart';
import '../utils/pos_stock_count_print.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_purchase_product_search_bar.dart';
import '../widgets/pos/pos_stock_count_helpers.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos_barcode_scanner.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

enum _LineFilter { all, matched, diff, unchecked }

class _CountLine {
  final String lineId;
  final String productId;
  final String? variantId;
  final String productCode;
  final String productName;
  final String unitName;
  final double systemQty;
  final double costPrice;
  final TextEditingController countedCtrl;

  _CountLine({
    required this.lineId,
    required this.productId,
    this.variantId,
    required this.productCode,
    required this.productName,
    this.unitName = 'Cái',
    this.systemQty = 0,
    this.costPrice = 0,
    double? countedQty,
  }) : countedCtrl = TextEditingController(
          text: tr(countedQty != null ? _formatQty(countedQty) : ''),
        );

  static String _formatQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  double? get countedQty {
    final t = countedCtrl.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  double get diffQty {
    final c = countedQty;
    if (c == null) return 0;
    return c - systemQty;
  }

  double get diffValue => diffQty * costPrice;

  bool get isMatched => countedQty != null && diffQty == 0;
  bool get hasDiff => countedQty != null && diffQty != 0;
  bool get isUnchecked => countedQty == null;

  Map<String, dynamic> toUpdateJson() => {
        'lineId': lineId,
        if (countedQty != null) 'countedQty': countedQty,
      };

  void dispose() => countedCtrl.dispose();

  factory _CountLine.fromApi(PosStockCountLine ln) => _CountLine(
        lineId: ln.id,
        productId: ln.productId,
        variantId: ln.variantId,
        productCode: ln.productCode,
        productName: ln.productName,
        unitName: ln.unitName ?? 'Cái',
        systemQty: ln.systemQty,
        costPrice: ln.costPrice,
        countedQty: ln.countedQty,
      );
}

class PosStockCountEditorScreen extends StatefulWidget {
  const PosStockCountEditorScreen({super.key, this.countId});

  final String? countId;

  @override
  State<PosStockCountEditorScreen> createState() =>
      _PosStockCountEditorScreenState();
}

class _PosStockCountEditorScreenState extends State<PosStockCountEditorScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _countNoCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');

  bool _loading = true;
  bool _saving = false;
  String? _countId;
  String _countNo = '';
  String _status = 'InProgress';
  _LineFilter _lineFilter = _LineFilter.all;
  final List<_CountLine> _lines = [];

  bool get _readOnly => _status != 'InProgress';

  @override
  void initState() {
    super.initState();
    _countId = widget.countId;
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _countNoCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    if (_countId != null && _countId!.isNotEmpty) {
      await _loadCount(_countId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyCount(PosStockCount c) {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ln in c.lines) {
      _lines.add(_CountLine.fromApi(ln));
    }
    _countId = c.id.isEmpty ? null : c.id;
    _countNo = c.countNo;
    _countNoCtrl.text = c.countNo;
    _status = c.status;
    _noteCtrl.text = c.note ?? '';
  }

  Future<void> _loadCount(String id) async {
    final res = await _api.getPosStockCount(id);
    if (!mounted || res['isSuccess'] != true) return;
    setState(() =>
        _applyCount(PosStockCount.fromJson(res['data'] as Map<String, dynamic>)));
  }

  Future<String?> _ensureCountId() async {
    if (_countId != null && _countId!.isNotEmpty) return _countId;
    final res = await _api.createPosStockCount({
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    });
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không tạo được phiếu');
      return null;
    }
    final c = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
    setState(() {
      _countId = c.id;
      _countNo = c.countNo;
      _countNoCtrl.text = c.countNo;
      _status = c.status;
    });
    return c.id;
  }

  List<_CountLine> get _filteredLines {
    return switch (_lineFilter) {
      _LineFilter.matched => _lines.where((l) => l.isMatched).toList(),
      _LineFilter.diff => _lines.where((l) => l.hasDiff).toList(),
      _LineFilter.unchecked => _lines.where((l) => l.isUnchecked).toList(),
      _ => _lines,
    };
  }

  double get _totalActualQty =>
      _lines.fold(0.0, (a, l) => a + (l.countedQty ?? 0));

  String _fmtQty(double v) => _qtyFmt.format(v);

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    final countId = await _ensureCountId();
    if (countId == null || !mounted) return;

    final key = '${pick.product.id}:${pick.variantId ?? 'base'}';
    if (_lines.any((l) => '${l.productId}:${l.variantId ?? 'base'}' == key)) {
      NotificationOverlayManager()
          .showWarning(title: 'Trùng', message: tr('Hàng đã có trong phiếu'));
      return;
    }

    final res = await _api.addPosStockCountLines(countId, [
      {
        'productId': pick.product.id,
        if (pick.variantId != null) 'variantId': pick.variantId,
      },
    ]);

    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      _applyCount(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
      setState(() {});
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không thêm được hàng');
    }
  }

  Future<void> _scanBarcode() async {
    if (_readOnly) return;
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _onPickProduct(pick);
  }

  Future<void> _removeLine(_CountLine line) async {
    if (_readOnly || _countId == null) return;
    final res = await _api.removePosStockCountLine(_countId!, line.lineId);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      _applyCount(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
      setState(() {});
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được dòng');
    }
  }

  void _adjustCounted(_CountLine line, double delta) {
    final cur = line.countedQty ?? line.systemQty;
    final next = (cur + delta).clamp(0, double.infinity);
    line.countedCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  Future<bool> _saveLinesAndNote() async {
    if ((_countId == null || _countId!.isEmpty) && _lines.isEmpty) {
      return false;
    }

    final countId = await _ensureCountId();
    if (countId == null) return false;

    if (_lines.isNotEmpty) {
      final lineRes = await _api.updatePosStockCountLines(
        countId,
        _lines.map((l) => l.toUpdateJson()).toList(),
      );
      if (lineRes['isSuccess'] != true) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: lineRes['message']?.toString() ?? 'Không lưu được dòng');
        return false;
      }
      _applyCount(
          PosStockCount.fromJson(lineRes['data'] as Map<String, dynamic>));
    }

    final noteRes = await _api.updatePosStockCount(countId, {
      'note': _noteCtrl.text.trim(),
    });
    if (noteRes['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: noteRes['message']?.toString() ?? 'Không lưu được ghi chú');
      return false;
    }
    _applyCount(PosStockCount.fromJson(noteRes['data'] as Map<String, dynamic>));
    return true;
  }

  Future<void> _saveDraft() async {
    if (_lines.isEmpty && (_countId == null || _countId!.isEmpty)) {
      NotificationOverlayManager().showWarning(
          title: 'Phiếu trống', message: tr('Thêm ít nhất một dòng hàng trước khi lưu'));
      return;
    }
    setState(() => _saving = true);
    final ok = await _saveLinesAndNote();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã lưu phiếu tạm', message: _countNo);
    }
  }

  Future<void> _complete() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Phiếu trống', message: tr('Thêm ít nhất một dòng hàng'));
      return;
    }
    final unchecked = _lines.where((l) => l.isUnchecked).length;
    if (unchecked > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Cân bằng kho')),
          content: Text(tr('Còn $unchecked dòng chưa nhập SL thực tế. Tiếp tục cân bằng kho?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: Text(tr('Tiếp tục')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    final saved = await _saveLinesAndNote();
    if (!saved || !mounted) {
      setState(() => _saving = false);
      return;
    }

    final res = await _api.completePosStockCount(_countId!);
    if (!mounted) return;
    setState(() => _saving = false);
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      statusFallback: 'InProgress',
      completedLabel: 'Đã cân bằng kho',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã cân bằng kho',
        message: result.successMessage(_countNo, completedLabel: 'Đã cân bằng kho'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không hoàn thành được',
      );
    }
  }

  Future<void> _printCount() async {
    if (_countId == null) return;
    final saved = await _saveLinesAndNote();
    if (!saved || !mounted) return;
    final res = await _api.getPosStockCount(_countId!);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: tr('Không tải được phiếu để in'));
      return;
    }
    final count = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await printPosStockCount(
      context: context,
      count: count,
      branchName: auth.currentUser?.department,
    );
  }

  Future<void> _deleteDraft() async {
    if (_countId == null || _countId!.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phiếu')),
        content: Text(tr('Xóa hẳn phiếu $_countNo?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosStockCount(_countId!);
    if (!mounted) return;
    final deleteResult = PosDocMutationResult.parseDelete(
      Map<String, dynamic>.from(res),
    );
    if (deleteResult.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: _countNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: deleteResult.errorMessage ?? res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _voidCompleted() async {
    if (_countId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu kiểm kê')),
        content: Text(tr('Hủy phiếu $_countNo và hoàn tồn kho về trước khi cân bằng?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy phiếu')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await _api.cancelPosStockCount(_countId!);
    if (!mounted) return;
    setState(() => _saving = false);
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Cancelled',
      statusFallback: 'InProgress',
      completedLabel: 'Đã cân bằng kho',
    );
    if (result.ok) {
      setState(() => _status = result.status);
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy',
        message: result.successMessage(_countNo,
            stockNote: 'Đã hoàn tồn kho', completedLabel: 'Đã cân bằng kho'),
      );
      await _loadCount(_countId!);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không hủy được',
      );
    }
  }

  Widget _filterTab(_LineFilter f, String label) {
    final active = _lineFilter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        onPressed: () => setState(() => _lineFilter = f),
        style: TextButton.styleFrom(
          foregroundColor: active ? _blue : PosTheme.textSecondary,
          backgroundColor: active ? _blue.withValues(alpha: 0.08) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: Text(tr(label),
            style: TextStyle(
                fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _countedCell(_CountLine l) {
    if (_readOnly) {
      return Text(
          tr(l.countedQty != null ? _fmtQty(l.countedQty!) : '—'),
          style: const TextStyle(fontSize: 13));
    }
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.remove, size: 18),
          onPressed: () => _adjustCounted(l, -1),
        ),
        Expanded(
          child: TextField(
            controller: l.countedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              hintText: tr('—'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.add, size: 18, color: _blue),
          onPressed: () => _adjustCounted(l, 1),
        ),
      ],
    );
  }

  Widget _buildLinesTable() {
    final visible = _filteredLines;

    Widget headerCell(String label, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(tr(label),
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
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _filterTab(_LineFilter.all, 'Tất cả (${_lines.length})'),
              _filterTab(_LineFilter.matched,
                  'Khớp (${_lines.where((l) => l.isMatched).length})'),
              _filterTab(_LineFilter.diff,
                  'Lệch (${_lines.where((l) => l.hasDiff).length})'),
              _filterTab(_LineFilter.unchecked,
                  'Chưa kiểm (${_lines.where((l) => l.isUnchecked).length})'),
            ],
          ),
        ),
        Container(
          color: const Color(0xFFF8FAFC),
          child: IntrinsicHeight(
            child: Row(
              children: [
                headerCell('STT', 1),
                headerCell('Mã', 2),
                headerCell('Tên', 4),
                headerCell('ĐVT', 1),
                headerCell('Tồn kho', 2),
                headerCell('Thực tế', 3),
                headerCell('SL lệch', 2),
                headerCell('Giá trị lệch', 2),
                if (!_readOnly) const SizedBox(width: 40),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    tr(_lines.isEmpty ? 'Chưa có hàng trong phiếu' : 'Không có dòng phù hợp bộ lọc'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (_, i) {
                    final l = visible[i];
                    final idx = _lines.indexOf(l) + 1;
                    final diffColor = l.countedQty == null
                        ? PosTheme.textSecondary
                        : l.diffQty == 0
                            ? Colors.green.shade700
                            : l.diffQty > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          dataCell(Text(tr('$idx'), style: const TextStyle(fontSize: 13)), 1),
                          dataCell(
                              Text(tr(l.productCode),
                                  style: const TextStyle(fontSize: 13, color: _blue)),
                              2),
                          dataCell(
                              Text(tr(l.productName),
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w500)),
                              4),
                          dataCell(Text(tr(l.unitName), style: const TextStyle(fontSize: 13)), 1),
                          dataCell(
                              Text(tr(_fmtQty(l.systemQty)),
                                  style: const TextStyle(fontSize: 13)),
                              2),
                          dataCell(_countedCell(l), 3),
                          dataCell(
                              Text(
                                  tr(l.countedQty != null
                                      ? '${l.diffQty >= 0 ? '+' : ''}${_fmtQty(l.diffQty)}'
                                      : '—'),
                                  style: TextStyle(fontSize: 13, color: diffColor)),
                              2),
                          dataCell(
                              Text(
                                  tr(l.countedQty != null
                                      ? '${_moneyFmt.format(l.diffValue)} đ'
                                      : '—'),
                                  style: TextStyle(fontSize: 13, color: diffColor)),
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

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canEdit('PosProducts')) {
      return Scaffold(body: Center(child: Text(tr('Không có quyền kiểm kê kho'))));
    }

    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.f3): _CountSearchIntent()},
      child: Actions(
        actions: {
          _CountSearchIntent: CallbackAction<_CountSearchIntent>(onInvoke: (_) => null),
        },
        child: Scaffold(
          backgroundColor: HrmPageChrome.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: PosTheme.textPrimary,
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.inventory_outlined, color: _blue, size: 22),
                const SizedBox(width: 8),
                Text(tr(_countId == null ? 'Kiểm kê kho' : 'Kiểm kê · $_countNo')),
              ],
            ),
            actions: [
              if (_countId != null && _lines.isNotEmpty)
                IconButton(
                  tooltip: tr('In phiếu'),
                  icon: const Icon(Icons.print_outlined),
                  onPressed: _printCount,
                ),
            ],
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
                                      hintText: tr('Tìm hàng hóa (F3)'),
                                      onPick: _onPickProduct,
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: Text(tr('Chi tiết phiếu kiểm kê'),
                                        style: TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.w600)),
                                  ),
                                IconButton(
                                  tooltip: tr('Quét mã vạch'),
                                  icon: const Icon(Icons.qr_code_scanner_outlined),
                                  onPressed: _readOnly ? null : _scanBarcode,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _lines.isEmpty && _readOnly
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.inventory_outlined,
                                            size: 48, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(tr('Phiếu không có dòng hàng'),
                                            style: TextStyle(color: Colors.grey.shade600)),
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
                            TextField(
                              controller: _countNoCtrl,
                              readOnly: true,
                              decoration: PosTheme.inputDecoration(
                                label: 'Mã KK',
                                hint: 'Mã phiếu tự động',
                              ),
                            ),
                            const SizedBox(height: 12),
                            InputDecorator(
                              decoration: PosTheme.inputDecoration(label: 'Trạng thái'),
                              child: stockCountStatusChip(_status),
                            ),
                            const Divider(height: 24),
                            _totalRow('Tổng SL thực tế (${_lines.length})',
                                _fmtQty(_totalActualQty),
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
                                child: Text(tr(_saving ? '…' : 'Lưu tạm')),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _saving ? null : _complete,
                                style: FilledButton.styleFrom(backgroundColor: _blue),
                                child: Text(tr(_saving ? '…' : 'Hoàn thành')),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _deleteDraft,
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: Text(tr('Xóa phiếu')),
                              ),
                            ] else if (_status == 'Cancelled') ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _deleteDraft,
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: Text(tr('Xóa phiếu')),
                              ),
                            ] else if (_status == 'Completed') ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _voidCompleted,
                                icon: const Icon(Icons.cancel_outlined, size: 18),
                                label: Text(tr('Hủy phiếu')),
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

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr(label), style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          Text(tr(value),
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  fontSize: bold ? 15 : 13)),
        ],
      ),
    );
  }
}

class _CountSearchIntent extends Intent {
  const _CountSearchIntent();
}
