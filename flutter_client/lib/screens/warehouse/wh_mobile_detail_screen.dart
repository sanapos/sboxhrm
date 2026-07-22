import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_purchase.dart';
import '../../models/pos_stock_count.dart';
import '../../models/pos_stock_issue_doc.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_doc_status.dart';
import '../../utils/pos_mutation_result.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import '../../widgets/warehouse/wh_mobile_components.dart';
import '../../widgets/warehouse/wh_mobile_doc_service.dart';
import '../../widgets/warehouse/wh_mobile_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import 'wh_mobile_editor_router.dart';

/// Chi tiết phiếu kho — xem nhanh, sửa hoặc hoàn thành.
class WhMobileDocDetailScreen extends StatefulWidget {
  const WhMobileDocDetailScreen({
    super.key,
    required this.docType,
    required this.docId,
  });

  final WhDocType docType;
  final String docId;

  @override
  State<WhMobileDocDetailScreen> createState() => _WhMobileDocDetailScreenState();
}

class _WhMobileDocDetailScreenState extends State<WhMobileDocDetailScreen> {
  final _api = ApiService();
  final _svc = WhMobileDocService();
  bool _loading = true;
  bool _acting = false;

  String _docNo = '';
  String _status = '';
  String? _subtitle;
  String? _note;
  String? _meta;
  double _amount = 0;
  int _lineCount = 0;
  List<Map<String, dynamic>> _lines = [];

  bool get _isDraft =>
      _status == widget.docType.draftStatus || _status == 'Draft';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      switch (widget.docType) {
        case WhDocType.purchaseReceipt:
          final res = await _api.getPosPurchaseReceipt(widget.docId);
          if (res['isSuccess'] == true) {
            final r = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
            _apply(r.receiptNo, r.status, r.supplierName, r.note,
                '${r.lines.length} dòng · ${_svc.formatDate(r.importDate ?? r.createdAt)}',
                r.grandTotal, r.lines.length,
                r.lines.map((l) => {
                      'name': l.productName,
                      'qty': l.qty,
                      'unit': l.unitName ?? '',
                      'total': l.lineTotal,
                    }).toList());
          }
        case WhDocType.purchaseReturn:
          final res = await _api.getPosPurchaseReturn(widget.docId);
          if (res['isSuccess'] == true) {
            final r = PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
            _apply(r.returnNo, r.status, r.supplierName, r.note,
                '${r.lines.length} dòng · ${_svc.formatDate(r.returnDate)}',
                r.totalAmount, r.lines.length,
                r.lines.map((l) => {
                      'name': l.productName,
                      'qty': l.qty,
                      'unit': l.unitName ?? '',
                      'total': l.lineTotal,
                    }).toList());
          }
        case WhDocType.stockCount:
          final res = await _api.getPosStockCount(widget.docId);
          if (res['isSuccess'] == true) {
            final c = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
            _apply(c.countNo, c.status, c.name, c.note,
                '${c.checkedCount}/${c.lineCount} đã kiểm · ${_svc.formatDate(c.createdAt)}',
                c.totalDiffValue.abs(), c.lineCount,
                c.lines.map((l) => {
                      'name': l.productName,
                      'qty': l.countedQty ?? l.systemQty,
                      'unit': l.unitName ?? '',
                      'total': l.diffValue,
                      'extra': 'TK: ${l.systemQty}',
                    }).toList());
          }
        case WhDocType.damageIssue:
        case WhDocType.internalUseIssue:
          final kind = widget.docType.stockIssueConfig!.kind;
          final res = await _api.getPosStockIssueDoc(kind, widget.docId);
          if (res['isSuccess'] == true) {
            final d = PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>);
            _apply(d.issueNo, d.status, d.recipientName ?? d.categoryName, d.note,
                '${d.lines.length} dòng · ${_svc.formatDate(d.createdAt)}',
                d.totalValue, d.lines.length,
                d.lines.map((l) => {
                      'name': l.productName,
                      'qty': l.qty,
                      'unit': l.unitName ?? '',
                      'total': l.lineTotal,
                    }).toList());
          }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(
    String no,
    String status,
    String? subtitle,
    String? note,
    String meta,
    double amount,
    int lineCount,
    List<Map<String, dynamic>> lines,
  ) {
    _docNo = no;
    _status = normalizePosDocStatus(status, fallback: widget.docType.draftStatus);
    _subtitle = subtitle;
    _note = note;
    _meta = meta;
    _amount = amount;
    _lineCount = lineCount;
    _lines = lines;
  }

  Future<void> _edit() async {
    final ok = await WhMobileEditorRouter.openEdit(
      context,
      widget.docType,
      widget.docId,
    );
    if (ok == true && mounted) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _complete() async {
    setState(() => _acting = true);
    Map<String, dynamic> res;
    switch (widget.docType) {
      case WhDocType.purchaseReceipt:
        res = await _api.completePosPurchaseReceipt(widget.docId);
      case WhDocType.purchaseReturn:
        res = await _api.completePosPurchaseReturn(widget.docId);
      case WhDocType.stockCount:
        res = await _api.completePosStockCount(widget.docId);
      case WhDocType.damageIssue:
      case WhDocType.internalUseIssue:
        res = await _api.completePosStockIssueDoc(
            widget.docType.stockIssueConfig!.kind, widget.docId);
    }
    if (!mounted) return;
    setState(() => _acting = false);
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      statusFallback: widget.docType.draftStatus,
      completedLabel: widget.docType.completeLabel,
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: widget.docType.completeLabel,
        message: result.successMessage(_docNo, completedLabel: widget.docType.completeLabel),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? '',
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text('Xóa hẳn phiếu $_docNo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: WhMobileTheme.danger),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _acting = true);
    Map<String, dynamic> res;
    switch (widget.docType) {
      case WhDocType.purchaseReceipt:
        res = await _api.deletePosPurchaseReceipt(widget.docId);
      case WhDocType.purchaseReturn:
        res = await _api.deletePosPurchaseReturn(widget.docId);
      case WhDocType.stockCount:
        res = await _api.deletePosStockCount(widget.docId);
      case WhDocType.damageIssue:
      case WhDocType.internalUseIssue:
        res = await _api.deletePosStockIssueDoc(
            widget.docType.stockIssueConfig!.kind, widget.docId);
    }
    if (!mounted) return;
    setState(() => _acting = false);
    final result = PosDocMutationResult.parseDelete(Map<String, dynamic>.from(res));
    if (result.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: _docNo);
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit(widget.docType.moduleCode) || perm.canEdit('PosProducts');

    return WhMobileScaffold(
      title: _docNo.isEmpty ? 'Chi tiết phiếu' : _docNo,
      subtitle: widget.docType.title,
      bottomBar: _loading
          ? null
          : WhMobileBottomBar(
              readOnly: !_isDraft || !canEdit,
              loading: _acting,
              onSaveDraft: _isDraft && canEdit ? _edit : null,
              saveDraftLabel: 'Chỉnh sửa',
              onComplete: _isDraft && canEdit ? _complete : null,
              completeLabel: widget.docType.completeLabel,
              dangerAction: _isDraft && canEdit
                  ? TextButton.icon(
                      onPressed: _acting ? null : _delete,
                      icon: Icon(Icons.delete_outline_rounded, color: WhMobileTheme.danger),
                      label: Text('Xóa phiếu', style: TextStyle(color: WhMobileTheme.danger)),
                    )
                  : null,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          WhStatusPill(
                            status: _status,
                            draftLabel: widget.docType.draftStatusLabel,
                          ),
                          const Spacer(),
                          Text(_svc.formatMoney(_amount), style: WhMobileTheme.money),
                        ],
                      ),
                      if (_subtitle != null) ...[
                        const SizedBox(height: 10),
                        Text(_subtitle!, style: WhMobileTheme.titleMedium.copyWith(fontSize: 15)),
                      ],
                      if (_meta != null) ...[
                        const SizedBox(height: 6),
                        Text(_meta!, style: WhMobileTheme.caption),
                      ],
                      if (_note != null && _note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Ghi chú', style: WhMobileTheme.label),
                        const SizedBox(height: 4),
                        Text(_note!, style: WhMobileTheme.body),
                      ],
                    ],
                  ),
                ),
                WhSectionHeader(title: 'Dòng hàng ($_lineCount)'),
                for (var i = 0; i < _lines.length; i++)
                  WhLineCard(
                    index: i + 1,
                    name: _lines[i]['name']?.toString() ?? '',
                    unit: _lines[i]['unit']?.toString(),
                    readOnly: true,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SL: ${_lines[i]['qty']}',
                          style: WhMobileTheme.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (_lines[i]['extra'] != null)
                          Text(_lines[i]['extra'].toString(), style: WhMobileTheme.caption),
                        Text(
                          _svc.formatMoney((_lines[i]['total'] as num?)?.toDouble() ?? 0),
                          style: WhMobileTheme.money.copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
