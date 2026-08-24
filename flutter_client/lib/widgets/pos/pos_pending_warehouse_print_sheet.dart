import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../utils/pos_kitchen_print.dart';
import '../../utils/pos_pending_print_store.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_sale_order_print.dart';
import '../pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bottom sheet phiếu in treo (HD / kho / bếp / tem) — thử lại / chọn máy / bỏ qua.
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
  Future<bool> Function(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetrySale,
  void Function(PendingSalePrintJob job)? onDismissSale,
  Future<bool> Function(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetryKitchen,
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
  final Future<bool> Function(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetrySale;
  final void Function(PendingSalePrintJob job)? onDismissSale;
  final Future<bool> Function(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetryKitchen;
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

  String _pickerKind(PosStorePrinter p) {
    if (p.isLabelPrinter) return 'Tem';
    if (p.isSunmi) return 'Sunmi';
    return p.connectionType;
  }

  Future<PosStorePrinter?> _pickPrinter({
    required String title,
    bool kitchenOnly = false,
  }) async {
    final deviceId = await PosPrintOrchestrator.stableDeviceId();
    var list = PosPrintOrchestrator.uniquePrintersForPicker(
      widget.printers,
      deviceId: deviceId,
    );
    if (kitchenOnly) {
      // Máy bếp + máy hóa đơn — khi máy bếp hỏng vẫn in phiếu ra Sunmi/USB hóa đơn.
      final kitchen = list.where((p) => p.canPrintKitchenSlip).toList();
      if (kitchen.isNotEmpty) {
        list = kitchen;
      } else {
        list = list.where((p) => !p.isLabelPrinter).toList();
      }
    }
    if (list.isEmpty) {
      setState(() => _statusMessage =
          'Chưa có máy in cloud/cửa hàng — mở Máy in cửa hàng rồi thử lại');
      return null;
    }
    return showDialog<PosStorePrinter>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: Text(tr(title)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              tr(
                kitchenOnly
                    ? '${list.length} máy nhiệt — bếp hoặc hóa đơn (khi máy bếp hỏng). '
                        'In ép lên máy chọn, chỉ món đang treo.'
                    : '${list.length} máy cửa hàng',
              ),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          for (final p in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  tr('${p.name} · ${_pickerKind(p)}'),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
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
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    if (result.anySuccess) {
      setState(() {
        _localJobs.removeWhere((j) => j.id == job.id);
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

  Future<void> _retrySale(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  }) async {
    final retry = widget.onRetrySale;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'sale:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(
      job,
      overridePrinterId: overridePrinterId,
      overridePrinter: overridePrinter,
    );
    if (!mounted) return;
    if (ok) {
      widget.onDismissSale?.call(job);
      setState(() {
        _localSaleJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = overridePrinter == null && overridePrinterId == null
            ? 'In lại hóa đơn thành công'
            : 'In lại hóa đơn trên máy đã chọn';
        _busyJobId = null;
      });
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại hóa đơn thất bại — thử chọn máy khác';
      _busyJobId = null;
    });
  }

  Future<void> _retryKitchen(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  }) async {
    final retry = widget.onRetryKitchen;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'kitchen:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(
      job,
      overridePrinterId: overridePrinterId,
      overridePrinter: overridePrinter,
    );
    if (!mounted) return;
    if (ok) {
      widget.onDismissKitchen?.call(job);
      setState(() {
        _localKitchenJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = overridePrinter == null && overridePrinterId == null
            ? 'In lại phiếu bếp thành công'
            : 'In lại phiếu bếp trên máy đã chọn';
        _busyJobId = null;
      });
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại phiếu bếp thất bại — thử chọn máy khác';
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

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                child: Row(
                  children: [
                    Icon(Icons.print_disabled_outlined,
                        size: 18, color: Colors.orange.shade800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('Phiếu chưa in ($_totalCount)'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.onDismissAll != null && _totalCount > 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
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
                        child: Text(tr('Bỏ hết'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    tr(_statusMessage!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.orange.shade900, fontSize: 11.5),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                  children: [
                    if (_localKitchenJobs.isNotEmpty) ...[
                      _sectionLabel('Bếp / hủy'),
                      for (final job in _localKitchenJobs)
                        _buildKitchenRow(job),
                    ],
                    if (_localCupJobs.isNotEmpty) ...[
                      _sectionLabel('Tem ly'),
                      for (final job in _localCupJobs) _buildCupRow(job),
                    ],
                    if (_localSaleJobs.isNotEmpty) ...[
                      _sectionLabel('Hóa đơn'),
                      for (final job in _localSaleJobs) _buildSaleRow(job),
                    ],
                    if (_localJobs.isNotEmpty) ...[
                      _sectionLabel('Xuất kho'),
                      for (final job in _localJobs) _buildWarehouseRow(job),
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

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
        child: Text(
          tr(text),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: PosTheme.textSecondary,
          ),
        ),
      );

  Widget _denseRow({
    required Color bg,
    required String title,
    required String subtitle,
    required String? error,
    required bool busy,
    required List<Widget> actions,
    required VoidCallback? onDismiss,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        tr(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PosTheme.textSecondary,
                          height: 1.15,
                        ),
                      ),
                    if ((error ?? '').isNotEmpty)
                      Text(
                        tr(error!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.red.shade700,
                          height: 1.15,
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ...actions,
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: tr('Bỏ qua'),
                onPressed: busy ? null : onDismiss,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String tip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: tr(tip),
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color ?? PosTheme.kiotBlue),
    );
  }

  Widget _buildKitchenRow(PendingKitchenPrintJob job) {
    final busy = _busyJobId == 'kitchen:${job.id}';
    final printer = (job.printerName ?? '').trim().isNotEmpty
        ? ' · ${job.printerName}'
        : '';
    return _denseRow(
      bg: const Color(0xFFFFFBEB),
      title: '${job.title} · ${job.tableName}$printer',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In phiếu bếp thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissKitchen?.call(job);
        setState(() => _localKitchenJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại',
          onPressed: () => _retryKitchen(job),
        ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Chọn máy khác',
          onPressed: () async {
            final p = await _pickPrinter(
              title: 'Chọn máy in phiếu bếp',
              kitchenOnly: true,
            );
            if (p == null || !mounted) return;
            await _retryKitchen(
              job,
              overridePrinterId: p.id,
              overridePrinter: p,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCupRow(PendingCupLabelPrintJob job) {
    final busy = _busyJobId == 'cup:${job.id}';
    final table = (job.tableLabel ?? '').trim();
    return _denseRow(
      bg: const Color(0xFFECFDF5),
      title: 'Tem ly × ${job.tickets.length}${table.isNotEmpty ? ' · $table' : ''}',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In tem ly thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissCup?.call(job);
        setState(() => _localCupJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại tem',
          onPressed: () => _retryCup(job),
        ),
      ],
    );
  }

  Widget _buildSaleRow(PendingSalePrintJob job) {
    final busy = _busyJobId == 'sale:${job.id}';
    return _denseRow(
      bg: const Color(0xFFEFF6FF),
      title: job.orderLabel,
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In hóa đơn thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissSale?.call(job);
        setState(() => _localSaleJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại hóa đơn',
          onPressed: () => _retrySale(job),
        ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Chọn máy khác',
          onPressed: () async {
            final p = await _pickPrinter(title: 'Chọn máy in hóa đơn');
            if (p == null || !mounted) return;
            await _retrySale(
              job,
              overridePrinterId: p.id,
              overridePrinter: p,
            );
          },
        ),
      ],
    );
  }

  Widget _buildWarehouseRow(PendingWarehousePrintJob job) {
    final busy = _busyJobId == job.id;
    final printer = job.printerName.isNotEmpty ? ' · ${job.printerName}' : '';
    return _denseRow(
      bg: const Color(0xFFFFF7ED),
      title: '${job.orderLabel}$printer',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? job.reason.label,
      busy: busy,
      onDismiss: () {
        widget.onDismiss(job);
        setState(() => _localJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        if (job.reason != PendingWarehousePrintReason.noPrinterAssignment)
          _action(
            icon: Icons.refresh,
            tip: 'In lại',
            onPressed: () =>
                _retry(job, WarehouseSlipPrintMethod.assigned),
          ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Máy khác',
          onPressed: () async {
            final p = await _pickPrinter(title: 'Chọn máy in xuất kho');
            if (p == null || !mounted) return;
            await _retry(
              job,
              WarehouseSlipPrintMethod.pickPrinter,
              overridePrinterId: p.id,
            );
          },
        ),
        _action(
          icon: Icons.settings_ethernet,
          tip: 'In cục bộ',
          onPressed: () =>
              _retry(job, WarehouseSlipPrintMethod.localThermal),
        ),
      ],
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
