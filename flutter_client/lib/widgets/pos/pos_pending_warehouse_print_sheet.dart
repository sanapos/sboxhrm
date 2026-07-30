import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../utils/pos_kitchen_print.dart';
import '../../utils/pos_pending_print_store.dart';
import '../../utils/pos_sale_order_print.dart';
import '../pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bottom sheet phiếu in treo (HD / kho / bếp / tem) — thử lại / bỏ qua.
Future<void> showPendingWarehousePrintSheet({
  required BuildContext context,
  required List<PendingWarehousePrintJob> jobs,
  List<PendingSalePrintJob> saleJobs = const [],
  List<PendingKitchenPrintJob> kitchenJobs = const [],
  List<PendingCupLabelPrintJob> cupJobs = const [],
  required List<PosStorePrinter> printers,
  required Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry,
  required void Function(PendingWarehousePrintJob job) onDismiss,
  Future<bool> Function(PendingSalePrintJob job)? onRetrySale,
  void Function(PendingSalePrintJob job)? onDismissSale,
  Future<bool> Function(PendingKitchenPrintJob job)? onRetryKitchen,
  void Function(PendingKitchenPrintJob job)? onDismissKitchen,
  Future<bool> Function(PendingCupLabelPrintJob job)? onRetryCup,
  void Function(PendingCupLabelPrintJob job)? onDismissCup,
  VoidCallback? onDismissAll,
}) async {
  if (jobs.isEmpty &&
      saleJobs.isEmpty &&
      kitchenJobs.isEmpty &&
      cupJobs.isEmpty) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    useSafeArea: true,
    builder: (ctx) {
      return _PendingWarehousePrintSheetBody(
        jobs: jobs,
        saleJobs: saleJobs,
        kitchenJobs: kitchenJobs,
        cupJobs: cupJobs,
        printers: printers,
        onRetry: onRetry,
        onDismiss: onDismiss,
        onRetrySale: onRetrySale,
        onDismissSale: onDismissSale,
        onRetryKitchen: onRetryKitchen,
        onDismissKitchen: onDismissKitchen,
        onRetryCup: onRetryCup,
        onDismissCup: onDismissCup,
        onDismissAll: onDismissAll,
      );
    },
  );
}

class _PendingWarehousePrintSheetBody extends StatefulWidget {
  const _PendingWarehousePrintSheetBody({
    required this.jobs,
    required this.saleJobs,
    required this.kitchenJobs,
    required this.cupJobs,
    required this.printers,
    required this.onRetry,
    required this.onDismiss,
    this.onRetrySale,
    this.onDismissSale,
    this.onRetryKitchen,
    this.onDismissKitchen,
    this.onRetryCup,
    this.onDismissCup,
    this.onDismissAll,
  });

  final List<PendingWarehousePrintJob> jobs;
  final List<PendingSalePrintJob> saleJobs;
  final List<PendingKitchenPrintJob> kitchenJobs;
  final List<PendingCupLabelPrintJob> cupJobs;
  final List<PosStorePrinter> printers;
  final Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry;
  final void Function(PendingWarehousePrintJob job) onDismiss;
  final Future<bool> Function(PendingSalePrintJob job)? onRetrySale;
  final void Function(PendingSalePrintJob job)? onDismissSale;
  final Future<bool> Function(PendingKitchenPrintJob job)? onRetryKitchen;
  final void Function(PendingKitchenPrintJob job)? onDismissKitchen;
  final Future<bool> Function(PendingCupLabelPrintJob job)? onRetryCup;
  final void Function(PendingCupLabelPrintJob job)? onDismissCup;
  final VoidCallback? onDismissAll;

  @override
  State<_PendingWarehousePrintSheetBody> createState() =>
      _PendingWarehousePrintSheetBodyState();
}

class _PendingWarehousePrintSheetBodyState
    extends State<_PendingWarehousePrintSheetBody> {
  String? _busyJobId;
  String? _statusMessage;
  late List<PendingWarehousePrintJob> _localJobs;
  late List<PendingSalePrintJob> _localSaleJobs;
  late List<PendingKitchenPrintJob> _localKitchenJobs;
  late List<PendingCupLabelPrintJob> _localCupJobs;

  @override
  void initState() {
    super.initState();
    _localJobs = List.from(widget.jobs);
    _localSaleJobs = List.from(widget.saleJobs);
    _localKitchenJobs = List.from(widget.kitchenJobs);
    _localCupJobs = List.from(widget.cupJobs);
  }

  int get _totalCount =>
      _localJobs.length +
      _localSaleJobs.length +
      _localKitchenJobs.length +
      _localCupJobs.length;

  Future<void> _retry(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) async {
    setState(() {
      _busyJobId = job.id;
      _statusMessage = null;
    });
    final result = await widget.onRetry(
      job,
      method,
      overridePrinterId: overridePrinterId,
    );
    if (!mounted) return;
    if (result.anySuccess && !result.hasFailures) {
      widget.onDismiss(job);
      setState(() => _localJobs.removeWhere((j) => j.id == job.id));
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    if (result.anySuccess) {
      setState(() {
        _statusMessage = result.summaryMessage(lineCount: job.lines.length);
        _busyJobId = null;
      });
      return;
    }
    setState(() {
      _statusMessage = result.summaryMessage(lineCount: job.lines.length);
      _busyJobId = null;
    });
  }

  Future<void> _retrySale(PendingSalePrintJob job) async {
    final retry = widget.onRetrySale;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'sale:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(job);
    if (!mounted) return;
    if (ok) {
      widget.onDismissSale?.call(job);
      setState(() {
        _localSaleJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = 'In lại hóa đơn thành công';
        _busyJobId = null;
      });
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại hóa đơn thất bại — thử lại hoặc kiểm tra máy in';
      _busyJobId = null;
    });
  }

  Future<void> _retryKitchen(PendingKitchenPrintJob job) async {
    final retry = widget.onRetryKitchen;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'kitchen:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(job);
    if (!mounted) return;
    if (ok) {
      widget.onDismissKitchen?.call(job);
      setState(() => _localKitchenJobs.removeWhere((j) => j.id == job.id));
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại phiếu bếp thất bại';
      _busyJobId = null;
    });
  }

  Future<void> _retryCup(PendingCupLabelPrintJob job) async {
    final retry = widget.onRetryCup;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'cup:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(job);
    if (!mounted) return;
    if (ok) {
      widget.onDismissCup?.call(job);
      setState(() => _localCupJobs.removeWhere((j) => j.id == job.id));
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại tem ly thất bại';
      _busyJobId = null;
    });
  }

  Future<void> _pickPrinterAndRetry(PendingWarehousePrintJob job) async {
    if (widget.printers.isEmpty) {
      setState(() => _statusMessage = 'Chưa có máy in cửa hàng');
      return;
    }
    final picked = await showDialog<PosStorePrinter>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: Text(tr('Chọn máy in')),
        children: widget.printers
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dlgCtx, p),
                child: Text(tr(p.name)),
              ),
            )
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    await _retry(
      job,
      WarehouseSlipPrintMethod.pickPrinter,
      overridePrinterId: picked.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.print_disabled_outlined,
                        color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('Phiếu chưa in ($_totalCount)'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.onDismissAll != null && _totalCount > 0)
                      TextButton(
                        onPressed: () {
                          widget.onDismissAll?.call();
                          setState(() {
                            _localJobs.clear();
                            _localSaleJobs.clear();
                            _localKitchenJobs.clear();
                            _localCupJobs.clear();
                          });
                          if (mounted) Navigator.pop(context);
                        },
                        child: Text(tr('Bỏ qua hết')),
                      ),
                  ],
                ),
              ),
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    tr(_statusMessage!),
                    style:
                        TextStyle(color: Colors.orange.shade900, fontSize: 13),
                  ),
                ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  if (_localKitchenJobs.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 4),
                      child: Text(tr('Phiếu bếp / hủy'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ),
                    for (final job in _localKitchenJobs) ...[
                      _buildKitchenCard(job),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (_localCupJobs.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 4, top: 4),
                      child: Text(tr('Tem dán ly'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ),
                    for (final job in _localCupJobs) ...[
                      _buildCupCard(job),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (_localSaleJobs.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 4, top: 4),
                      child: Text(tr('Hóa đơn bán'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ),
                    for (final job in _localSaleJobs) ...[
                      _buildSaleCard(job),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (_localJobs.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 4, top: 4),
                      child: Text(tr('Phiếu xuất kho'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ),
                    for (var i = 0; i < _localJobs.length; i++) ...[
                      _buildWarehouseCard(_localJobs[i]),
                      if (i < _localJobs.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildKitchenCard(PendingKitchenPrintJob job) {
    final busy = _busyJobId == 'kitchen:${job.id}';
    return Material(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('${job.title} · ${job.tableName}'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Bỏ qua'),
                  onPressed: busy
                      ? null
                      : () {
                          widget.onDismissKitchen?.call(job);
                          setState(() => _localKitchenJobs
                              .removeWhere((j) => j.id == job.id));
                          if (_totalCount == 0 && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(tr(job.lineSummary), style: const TextStyle(fontSize: 13)),
            Text(
              tr(job.errorMessage ?? 'In phiếu bếp thất bại'),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _retryKitchen(job),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr('In lại phiếu bếp')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupCard(PendingCupLabelPrintJob job) {
    final busy = _busyJobId == 'cup:${job.id}';
    return Material(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Tem ly × ${job.tickets.length}'
                    '${(job.tableLabel ?? '').isNotEmpty ? ' · ${job.tableLabel}' : ''}'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Bỏ qua'),
                  onPressed: busy
                      ? null
                      : () {
                          widget.onDismissCup?.call(job);
                          setState(() =>
                              _localCupJobs.removeWhere((j) => j.id == job.id));
                          if (_totalCount == 0 && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(tr(job.lineSummary), style: const TextStyle(fontSize: 13)),
            Text(
              tr(job.errorMessage ?? 'In tem ly thất bại'),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _retryCup(job),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr('In lại tem')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleCard(PendingSalePrintJob job) {
    final busy = _busyJobId == 'sale:${job.id}';
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(job.orderLabel),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Bỏ qua'),
                  onPressed: busy
                      ? null
                      : () {
                          widget.onDismissSale?.call(job);
                          setState(() =>
                              _localSaleJobs.removeWhere((j) => j.id == job.id));
                          if (_totalCount == 0 && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(tr(job.lineSummary), style: const TextStyle(fontSize: 13)),
            Text(
              tr(job.errorMessage ?? 'In hóa đơn thất bại'),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _retrySale(job),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr('In lại hóa đơn')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseCard(PendingWarehousePrintJob job) {
    final busy = _busyJobId == job.id;
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(job.orderLabel),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Bỏ qua'),
                  onPressed: busy
                      ? null
                      : () {
                          widget.onDismiss(job);
                          setState(() =>
                              _localJobs.removeWhere((j) => j.id == job.id));
                          if (_totalCount == 0 && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(tr(job.lineSummary), style: const TextStyle(fontSize: 13)),
            if (job.printerName.isNotEmpty)
              Text(tr('Máy in: ${job.printerName}'),
                style: const TextStyle(
                  fontSize: 12,
                  color: PosTheme.textSecondary,
                ),
              ),
            Text(
              tr(job.errorMessage ?? job.reason.label),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (job.reason !=
                      PendingWarehousePrintReason.noPrinterAssignment)
                    OutlinedButton.icon(
                      onPressed: () => _retry(
                        job,
                        WarehouseSlipPrintMethod.assigned,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(tr('In lại')),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _pickPrinterAndRetry(job),
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: Text(tr('Máy khác')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _retry(
                      job,
                      WarehouseSlipPrintMethod.localThermal,
                    ),
                    icon: const Icon(Icons.settings_ethernet, size: 16),
                    label: Text(tr('In cục bộ')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _retry(
                      job,
                      WarehouseSlipPrintMethod.htmlPreview,
                    ),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: Text(tr('HTML')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Nút máy in có badge phiếu treo trên header thu ngân.
class PosPendingPrintIconButton extends StatelessWidget {
  const PosPendingPrintIconButton({
    super.key,
    required this.pendingCount,
    required this.onTap,
    this.iconColor = Colors.white,
    this.compact = false,
  });

  final int pendingCount;
  final VoidCallback onTap;
  final Color iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr(pendingCount > 0
              ? 'Phiếu chưa in ($pendingCount)'
              : 'Phiếu in treo'),
          icon: Icon(
            pendingCount > 0
                ? Icons.print_disabled_outlined
                : Icons.receipt_long_outlined,
            size: compact ? 22 : 22,
            color: pendingCount > 0 ? Colors.orange.shade200 : iconColor,
          ),
          onPressed: onTap,
        ),
        if (pendingCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                tr(pendingCount > 99 ? '99+' : '$pendingCount'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
