import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../utils/pos_kitchen_print.dart';
import '../pos/pos_theme.dart';

/// Bottom sheet phiếu in kho treo — cho phép thử lại / chọn phương thức in khác.
Future<void> showPendingWarehousePrintSheet({
  required BuildContext context,
  required List<PendingWarehousePrintJob> jobs,
  required List<PosStorePrinter> printers,
  required Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry,
  required void Function(PendingWarehousePrintJob job) onDismiss,
  VoidCallback? onDismissAll,
}) async {
  if (jobs.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _PendingWarehousePrintSheetBody(
        jobs: jobs,
        printers: printers,
        onRetry: onRetry,
        onDismiss: onDismiss,
        onDismissAll: onDismissAll,
      );
    },
  );
}

class _PendingWarehousePrintSheetBody extends StatefulWidget {
  const _PendingWarehousePrintSheetBody({
    required this.jobs,
    required this.printers,
    required this.onRetry,
    required this.onDismiss,
    this.onDismissAll,
  });

  final List<PendingWarehousePrintJob> jobs;
  final List<PosStorePrinter> printers;
  final Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry;
  final void Function(PendingWarehousePrintJob job) onDismiss;
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

  @override
  void initState() {
    super.initState();
    _localJobs = List.from(widget.jobs);
  }

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
      if (_localJobs.isEmpty && mounted) Navigator.pop(context);
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

  Future<void> _pickPrinterAndRetry(PendingWarehousePrintJob job) async {
    if (widget.printers.isEmpty) {
      setState(() => _statusMessage = 'Chưa có máy in cửa hàng');
      return;
    }
    final picked = await showDialog<PosStorePrinter>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: const Text('Chọn máy in'),
        children: widget.printers
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dlgCtx, p),
                child: Text(p.name),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
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
                    child: Text(
                      'Phiếu kho chưa in (${_localJobs.length})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.onDismissAll != null && _localJobs.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        widget.onDismissAll?.call();
                        setState(() => _localJobs.clear());
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text('Bỏ qua hết'),
                    ),
                ],
              ),
            ),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: _localJobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final job = _localJobs[i];
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
                                  job.orderLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Bỏ qua',
                                onPressed: busy
                                    ? null
                                    : () {
                                        widget.onDismiss(job);
                                        setState(() =>
                                            _localJobs.removeWhere(
                                                (j) => j.id == job.id));
                                        if (_localJobs.isEmpty &&
                                            context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                          Text(
                            job.lineSummary,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (job.printerName.isNotEmpty)
                            Text(
                              'Máy in: ${job.printerName}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: PosTheme.textSecondary,
                              ),
                            ),
                          Text(
                            job.errorMessage ?? job.reason.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
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
                                    PendingWarehousePrintReason
                                        .noPrinterAssignment)
                                  OutlinedButton.icon(
                                    onPressed: () => _retry(
                                      job,
                                      WarehouseSlipPrintMethod.assigned,
                                    ),
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('In lại'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => _pickPrinterAndRetry(job),
                                  icon: const Icon(Icons.print_outlined,
                                      size: 16),
                                  label: const Text('Máy khác'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _retry(
                                    job,
                                    WarehouseSlipPrintMethod.localThermal,
                                  ),
                                  icon: const Icon(Icons.settings_ethernet,
                                      size: 16),
                                  label: const Text('In cục bộ'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _retry(
                                    job,
                                    WarehouseSlipPrintMethod.htmlPreview,
                                  ),
                                  icon: const Icon(Icons.description_outlined,
                                      size: 16),
                                  label: const Text('HTML'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
          tooltip: pendingCount > 0
              ? 'Phiếu kho chưa in ($pendingCount)'
              : 'Phiếu in kho',
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
                pendingCount > 99 ? '99+' : '$pendingCount',
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
