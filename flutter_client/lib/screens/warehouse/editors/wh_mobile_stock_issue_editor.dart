import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/pos_stock_issue_doc.dart';
import '../../../services/api_service.dart';
import '../../../utils/pos_doc_status.dart';
import '../../../utils/pos_mutation_result.dart';
import '../../../utils/pos_purchase_product_lookup.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/notification_overlay.dart';
import '../../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../../../widgets/pos/pos_stock_issue_config.dart';
import '../../../widgets/pos_barcode_scanner.dart';
import '../../../widgets/warehouse/wh_doc_type.dart';
import '../../../widgets/warehouse/wh_mobile_components.dart';
import '../../../widgets/warehouse/wh_mobile_theme.dart';
import '../../main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class WhMobileStockIssueEditor extends StatefulWidget {
  const WhMobileStockIssueEditor({
    super.key,
    required this.docType,
    this.issueId,
  });

  final WhDocType docType;
  final String? issueId;

  @override
  State<WhMobileStockIssueEditor> createState() => _WhMobileStockIssueEditorState();
}

class _Line {
  _Line({
    required this.lineId,
    required this.productId,
    required this.name,
    this.code,
    this.unit,
    double qty = 1,
    double cost = 0,
  })  : qty = qty,
        cost = cost;

  final String lineId;
  final String productId;
  final String name;
  final String? code;
  final String? unit;
  double qty;
  double cost;
}

class _WhMobileStockIssueEditorState extends State<WhMobileStockIssueEditor> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  PosStockIssueConfig get _config => widget.docType.stockIssueConfig!;
  bool _loading = true;
  bool _saving = false;
  String? _issueId;
  String _issueNo = '';
  String _status = 'Draft';
  String? _categoryName;
  final List<_Line> _lines = [];

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
    _recipientCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_issueId != null && _issueId!.isNotEmpty) {
      final res = await _api.getPosStockIssueDoc(_config.kind, _issueId!);
      if (mounted && res['isSuccess'] == true) {
        _applyDoc(PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyDoc(PosStockIssueDoc doc) {
    _issueId = doc.id.isEmpty ? null : doc.id;
    _issueNo = doc.issueNo;
    _status = normalizePosDocStatus(doc.status);
    _noteCtrl.text = doc.note ?? '';
    _categoryName = doc.categoryName;
    _recipientCtrl.text = doc.recipientName ?? '';
    _lines
      ..clear()
      ..addAll(doc.lines.map((l) => _Line(
            lineId: l.id,
            productId: l.productId,
            name: l.productName,
            code: l.productCode,
            unit: l.unitName,
            qty: l.qty > 0 ? l.qty : 1,
            cost: l.costPrice,
          )));
  }

  PosStockIssueDoc _docFromRes(Map<String, dynamic> res) =>
      PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>);

  Future<String?> _ensureId() async {
    if (_issueId != null && _issueId!.isNotEmpty) return _issueId;
    final res = await _api.createPosStockIssueDoc(_config.kind, _headerBody());
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không tạo được phiếu');
      return null;
    }
    _applyDoc(_docFromRes(res));
    return _issueId;
  }

  Map<String, dynamic> _headerBody() => {
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (_config.showInternalFields) ...{
          'categoryName': _categoryName,
          'recipientName': _recipientCtrl.text.trim().isEmpty
              ? null
              : _recipientCtrl.text.trim(),
        },
      };

  Future<void> _pickProduct(PosPurchaseLookupPick pick) async {
    if (_readOnly) return;
    final addQty = (pick.qty == null || pick.qty! <= 0) ? 1.0 : pick.qty!;
    final existing = _lines.where((l) => l.productId == pick.product.id).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty += addQty);
      return;
    }
    final id = await _ensureId();
    if (id == null || !mounted) return;
    final res = await _api.addPosStockIssueDocLines(_config.kind, id, [
      {
        'productId': pick.product.id,
        if (pick.variantId != null) 'variantId': pick.variantId,
      },
    ]);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _applyDoc(_docFromRes(res));
        for (final line in _lines) {
          if (line.productId == pick.product.id) {
            line.qty = addQty;
            break;
          }
        }
      });
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không thêm được hàng');
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _pickProduct(pick);
  }

  Future<void> _removeLine(_Line line) async {
    if (_readOnly || _issueId == null) return;
    final res = await _api.removePosStockIssueDocLine(_config.kind, _issueId!, line.lineId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() => _applyDoc(_docFromRes(res)));
    }
  }

  Future<bool> _persist() async {
    if (_lines.isEmpty && (_issueId == null || _issueId!.isEmpty)) return false;
    final id = await _ensureId();
    if (id == null) return false;

    if (_lines.isNotEmpty) {
      final lineRes = await _api.updatePosStockIssueDocLines(
        _config.kind,
        id,
        _lines
            .map((l) => {
                  'lineId': l.lineId,
                  'qty': l.qty,
                  'costPrice': l.cost,
                })
            .toList(),
      );
      if (lineRes['isSuccess'] != true) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: lineRes['message']?.toString() ?? 'Không lưu được dòng');
        return false;
      }
      _applyDoc(_docFromRes(lineRes));
    }

    final hdr = await _api.updatePosStockIssueDoc(_config.kind, id, _headerBody());
    if (hdr['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: hdr['message']?.toString() ?? 'Không lưu được phiếu');
      return false;
    }
    return true;
  }

  Future<void> _saveDraft() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm ít nhất một dòng hàng'));
      return;
    }
    setState(() => _saving = true);
    final ok = await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã lưu nháp', message: _issueNo);
    }
  }

  Future<void> _complete() async {
    if (_lines.isEmpty || _lines.every((l) => l.qty <= 0)) {
      NotificationOverlayManager().showWarning(title: 'Số lượng', message: tr('Nhập SL > 0'));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(_config.completeDialogTitle)),
        content: Text(tr(_config.completeDialogMessage)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xác nhận'))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    final saved = await _persist();
    if (!saved || !mounted) {
      setState(() => _saving = false);
      return;
    }
    final res = await _api.completePosStockIssueDoc(_config.kind, _issueId!);
    if (!mounted) return;
    setState(() => _saving = false);
    final result = PosDocMutationResult.parse(Map<String, dynamic>.from(res), expectedStatus: 'Completed');
    if (result.ok) {
      NotificationOverlayManager().showSuccess(title: 'Hoàn thành', message: _issueNo);
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: result.errorMessage ?? res['message']?.toString() ?? '');
    }
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.qty * l.cost);

  @override
  Widget build(BuildContext context) {
    return WhMobileScaffold(
      title: _issueNo.isEmpty ? widget.docType.createLabel : _issueNo,
      subtitle: widget.docType.title,
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
        completeLabel: widget.docType.completeLabel,
      ),
      body: _loading
          ? const Center(child: LoadingWidget())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      WhMobileTheme.padH,
                      WhMobileTheme.gap,
                      WhMobileTheme.padH,
                      16,
                    ),
                    children: [
                      if (_config.showInternalFields) ...[
                        WhGlassCard(
                          child: Column(
                            children: [
                              DropdownButtonFormField<String>(
                                value: _categoryName,
                                decoration: WhMobileTheme.fieldDecoration(label: 'Danh mục'),
                                items: const [
                                  'Tiêu hao',
                                  'Marketing',
                                  'Bảo trì',
                                  'Khác',
                                ]
                                    .map((c) => DropdownMenuItem(value: c, child: Text(tr(c))))
                                    .toList(),
                                onChanged: _readOnly
                                    ? null
                                    : (v) => setState(() => _categoryName = v),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _recipientCtrl,
                                readOnly: _readOnly,
                                decoration: WhMobileTheme.fieldDecoration(label: 'Người nhận'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: WhMobileTheme.gap),
                      ],
                      if (!_readOnly)
                        PosPurchaseProductSearchBar(
                          api: _api,
                          hintText: tr('Tìm hoặc quét mã hàng…'),
                          onPick: _pickProduct,
                        ),
                      const SizedBox(height: WhMobileTheme.gap),
                      WhSectionHeader(title: 'Hàng hóa (${_lines.length})'),
                      if (_lines.isEmpty)
                        WhEmptyState(
                          icon: widget.docType.icon,
                          title: 'Chưa có hàng',
                          subtitle: 'Quét mã hoặc tìm sản phẩm ở trên',
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
                            onRemove: () => _removeLine(l),
                            child: WhQtyStepper(
                              label: _config.qtyColumnLabel,
                              value: l.qty,
                              readOnly: _readOnly,
                              onChanged: (v) => setState(() => l.qty = v),
                            ),
                            trailing: Text(
                              tr(_moneyFmt.format(l.qty * l.cost)),
                              style: WhMobileTheme.money.copyWith(fontSize: 15),
                            ),
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
                ),
                if (_lines.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: WhMobileTheme.card(radius: WhMobileTheme.radiusMd),
                    child: WhSummaryRow(
                      label: 'Tổng giá trị',
                      value: '${_moneyFmt.format(_total)} đ',
                      bold: true,
                    ),
                  ),
              ],
            ),
    );
  }
}
