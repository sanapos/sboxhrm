import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/pos_stock_count.dart';
import '../../../services/api_service.dart';
import '../../../utils/pos_doc_status.dart';
import '../../../utils/pos_mutation_result.dart';
import '../../../utils/pos_purchase_product_lookup.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/notification_overlay.dart';
import '../../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../../../widgets/pos_barcode_scanner.dart';
import '../../../widgets/warehouse/wh_mobile_components.dart';
import '../../../widgets/warehouse/wh_mobile_theme.dart';
import '../../main_layout.dart' show ScreenRefreshNotifier;
import 'package:sbox_pos/l10n/app_tr.dart';

class WhMobileStockCountEditor extends StatefulWidget {
  const WhMobileStockCountEditor({super.key, this.countId});

  final String? countId;

  @override
  State<WhMobileStockCountEditor> createState() => _WhMobileStockCountEditorState();
}

class _CountLine {
  _CountLine({
    required this.lineId,
    required this.productId,
    required this.name,
    this.code,
    this.unit,
    this.systemQty = 0,
    double? countedQty,
  }) : countedQty = countedQty;

  final String lineId;
  final String productId;
  final String name;
  final String? code;
  final String? unit;
  final double systemQty;
  double? countedQty;

  double get diff => (countedQty ?? systemQty) - systemQty;
  bool get isUnchecked => countedQty == null;
}

class _WhMobileStockCountEditorState extends State<WhMobileStockCountEditor> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');

  bool _loading = true;
  bool _saving = false;
  String? _countId;
  String _countNo = '';
  String _status = 'InProgress';
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
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_countId != null && _countId!.isNotEmpty) {
      final res = await _api.getPosStockCount(_countId!);
      if (mounted && res['isSuccess'] == true) {
        _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(PosStockCount c) {
    _countId = c.id.isEmpty ? null : c.id;
    _countNo = c.countNo;
    _status = normalizePosDocStatus(c.status, fallback: 'InProgress');
    _noteCtrl.text = c.note ?? '';
    _lines
      ..clear()
      ..addAll(c.lines.map((l) => _CountLine(
            lineId: l.id,
            productId: l.productId,
            name: l.productName,
            code: l.productCode,
            unit: l.unitName,
            systemQty: l.systemQty,
            countedQty: l.countedQty,
          )));
  }

  Future<String?> _ensureId() async {
    if (_countId != null && _countId!.isNotEmpty) return _countId;
    final res = await _api.createPosStockCount({
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không tạo được phiếu');
      return null;
    }
    final c = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
    setState(() => _apply(c));
    return c.id;
  }

  Future<void> _pickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    final addQty = (pick.qty == null || pick.qty! <= 0) ? 1.0 : pick.qty!;
    final existing = _lines.where((l) => l.productId == pick.product.id).toList();
    if (existing.isNotEmpty) {
      setState(() {
        final cur = existing.first.countedQty ?? existing.first.systemQty;
        existing.first.countedQty = cur + addQty;
      });
      return;
    }
    final id = await _ensureId();
    if (id == null || !mounted) return;
    final res = await _api.addPosStockCountLines(id, [
      {
        'productId': pick.product.id,
        if (pick.variantId != null) 'variantId': pick.variantId,
      },
    ]);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
        for (final line in _lines) {
          if (line.productId == pick.product.id) {
            line.countedQty = addQty;
            break;
          }
        }
      });
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _pickProduct(pick);
  }

  Future<void> _removeLine(_CountLine line) async {
    if (_readOnly || _countId == null) return;
    final res = await _api.removePosStockCountLine(_countId!, line.lineId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() => _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>)));
    }
  }

  Future<bool> _persist() async {
    if (_lines.isEmpty && (_countId == null || _countId!.isEmpty)) return false;
    final id = await _ensureId();
    if (id == null) return false;

    if (_lines.isNotEmpty) {
      final lineRes = await _api.updatePosStockCountLines(
        id,
        _lines
            .map((l) => {
                  'lineId': l.lineId,
                  if (l.countedQty != null) 'countedQty': l.countedQty,
                })
            .toList(),
      );
      if (lineRes['isSuccess'] != true) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: lineRes['message']?.toString() ?? 'Không lưu được dòng');
        return false;
      }
      _apply(PosStockCount.fromJson(lineRes['data'] as Map<String, dynamic>));
    }

    final noteRes = await _api.updatePosStockCount(id, {'note': _noteCtrl.text.trim()});
    if (noteRes['isSuccess'] != true) return false;
    return true;
  }

  Future<void> _saveDraft() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm hàng trước khi lưu'));
      return;
    }
    setState(() => _saving = true);
    final ok = await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) NotificationOverlayManager().showSuccess(title: 'Đã lưu nháp', message: _countNo);
  }

  Future<void> _complete() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm hàng trước'));
      return;
    }
    setState(() => _saving = true);
    final saved = await _persist();
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
      completedLabel: 'Cân bằng kho',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(title: 'Cân bằng kho', message: _countNo);
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: result.errorMessage ?? res['message']?.toString() ?? '');
    }
  }

  int get _unchecked => _lines.where((l) => l.isUnchecked).length;

  @override
  Widget build(BuildContext context) {
    return WhMobileScaffold(
      title: _countNo.isEmpty ? 'Tạo phiếu KK' : _countNo,
      subtitle: _unchecked > 0 ? 'Còn $_unchecked dòng chưa kiểm' : 'Kiểm kho',
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
        onSaveDraft: _readOnly ? null : _saveDraft,
        onComplete: _readOnly ? null : _complete,
        completeLabel: 'Cân bằng kho',
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
                if (!_readOnly)
                  PosPurchaseProductSearchBar(
                    api: _api,
                    hintText: tr('Tìm hoặc quét mã hàng…'),
                    onPick: _pickProduct,
                  ),
                const SizedBox(height: WhMobileTheme.gap),
                WhSectionHeader(title: 'Kiểm đếm (${_lines.length})'),
                if (_lines.isEmpty)
                  const WhEmptyState(
                    icon: Icons.fact_check_rounded,
                    title: 'Chưa có hàng',
                    subtitle: 'Thêm sản phẩm cần kiểm kho',
                  )
                else
                  ...List.generate(_lines.length, (i) {
                    final l = _lines[i];
                    final counted = l.countedQty ?? l.systemQty;
                    return WhLineCard(
                      index: i + 1,
                      name: l.name,
                      code: l.code,
                      unit: l.unit,
                      readOnly: _readOnly,
                      onRemove: () => _removeLine(l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WhSummaryRow(
                            label: 'Tồn hệ thống',
                            value: _qtyFmt.format(l.systemQty),
                          ),
                          const SizedBox(height: 8),
                          WhQtyStepper(
                            label: 'SL thực tế',
                            value: counted,
                            readOnly: _readOnly,
                            onChanged: (v) => setState(() => l.countedQty = v),
                          ),
                        ],
                      ),
                      trailing: l.diff != 0
                          ? Text(tr('Lệch: ${_qtyFmt.format(l.diff)}'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: l.diff > 0 ? WhMobileTheme.accent : WhMobileTheme.danger,
                              ),
                            )
                          : Text(tr('Khớp ✓'), style: TextStyle(color: WhMobileTheme.accent, fontWeight: FontWeight.w600)),
                    );
                  }),
                const SizedBox(height: WhMobileTheme.gap),
                WhGlassCard(
                  child: TextField(
                    controller: _noteCtrl,
                    readOnly: _readOnly,
                    maxLines: 2,
                    decoration: WhMobileTheme.fieldDecoration(label: 'Ghi chú'),
                  ),
                ),
              ],
            ),
    );
  }
}
